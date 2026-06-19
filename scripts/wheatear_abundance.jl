#=
Hierarchical Bayesian abundance model for Wheatear counts (2000–2022).

Observation types in the data:
  type = 1  exact count       → likelihood  = PMF(λ, l)
  type = 2  right-censored    → likelihood  = 1 − CDF(λ, l)        [P(X > l)]
  type = 3  interval-censored → likelihood  = CDF(λ, u) − CDF(λ, l) [P(l < X ≤ u)]

The Poisson CDF is evaluated by summing PMF terms (logsumexp) rather than calling
logcdf(Poisson, ·) so that Turing's AD (which passes DualNumber parameters) never
hits the StatsFuns regularised-gamma code path that does not support dual numbers.

Model structure (log-linear, non-centred parameterisation):
  log λᵢ = μ + α[site[i]] + γ[year[i]] + β₁·doy_z[i] + β₂·doy_z[i]²

  α[s]  ~ Normal(0, σ_α)   (site random effect)
  γ[y]  ~ Normal(0, σ_γ)   (year random effect)
  μ     ~ Normal(log 3, 1.5)
  β₁,β₂ ~ Normal(0, 1)
  σ_α, σ_γ ~ Exponential(1)

Run with multiple threads for multi-chain sampling:
  julia -t auto --project=. scripts/wheatear_abundance.jl
=#

using DrWatson
@quickactivate "ABC"

using DataFramesMeta, DataFrames
using Parquet2
using Dates
using Turing, Distributions
using MCMCChains: summarystats
using LogExpFunctions          # logsumexp, log1mexp
using StatsBase: countmap, mean, std
using CairoMakie
using Serialization            # serialize / deserialize

# ─────────────────────────────────────────────────────────────────────────────
# 1.  Load data
# ─────────────────────────────────────────────────────────────────────────────

raw = DataFrame(Parquet2.Dataset(datadir("exp_pro", "wheatear.parquet")))

# Parquet2 may return PooledVectors; collect to plain Vectors for dropmissing
df = mapcols(collect, raw)
dropmissing!(df, [:type, :L, :U])

println("Loaded $(nrow(df)) observations after dropping missing type/L/U.")
println("Type counts: ", sort(collect(countmap(df.type)), by = first))

# ─────────────────────────────────────────────────────────────────────────────
# 2.  Feature engineering
# ─────────────────────────────────────────────────────────────────────────────

@rtransform! df begin
    :yr  = year(:Date)
    :doy = dayofyear(:Date)
end

# Integer indices for sites and years
sites    = sort(unique(df.Gridref))
yrs      = sort(unique(df.yr))
site_map = Dict(s => i for (i, s) in enumerate(sites))
year_map = Dict(y => i for (i, y) in enumerate(yrs))

@rtransform! df begin
    :site_idx = site_map[:Gridref]
    :year_idx = year_map[:yr]
end

n_sites = length(sites)
n_years = length(yrs)
N       = nrow(df)

println("$N observations | $n_sites sites | $n_years years ($(first(yrs))–$(last(yrs)))")

# Standardise DOY → mean 0, SD 1 for numerical stability
doy_μ = mean(df.doy)
doy_σ = std(df.doy)
doy_z = (df.doy .- doy_μ) ./ doy_σ

# Extract plain vectors (avoids type instability inside the model loop)
L_obs    = Int.(df.L)
U_obs    = Int.(df.U)
type_obs = Int.(df.type)
site_idx = Int.(df.site_idx)
year_idx = Int.(df.year_idx)

# ─────────────────────────────────────────────────────────────────────────────
# 3.  AD-safe Poisson log-probability helpers
#
#  poisson_logpmf delegates to Distributions.logpdf(Poisson(λ), k).
#    k is integer data; lgamma(k+1) is a constant w.r.t. λ, so no dual-number
#    issues arise (the AD trouble only surfaces in logcdf which passes λ to the
#    regularised incomplete gamma function).
#
#  log_rightcensored(λ, l)  = log(1 − CDF(λ, l)) = log P(X > l)
#  log_interval(λ, l, u)    = log(CDF(λ, u) − CDF(λ, l)) = log P(l < X ≤ u)
# ─────────────────────────────────────────────────────────────────────────────

@inline poisson_logpmf(λ, k) = logpdf(Poisson(λ), k)

"""
    log_rightcensored(λ, l)

log P(X > l) for X ~ Poisson(λ).
Computed as log1mexp(logsumexp(PMF over 0..l)) to remain AD-compatible.
"""
function log_rightcensored(λ, l)
    log_cdf = logsumexp(poisson_logpmf(λ, k) for k in 0:l)
    # logsumexp can round to +ε when the CDF is numerically 1; guard before log1mexp
    log_cdf >= 0 && return oftype(log_cdf, -Inf)  # P(X > l) = 0
    return log1mexp(log_cdf)
end

"""
    log_interval(λ, l, u)

log(CDF(λ, u) − CDF(λ, l)) = log P(l < X ≤ u) for X ~ Poisson(λ).
"""
function log_interval(λ, l, u)
    return logsumexp(poisson_logpmf(λ, k) for k in (l + 1):u)
end

# ─────────────────────────────────────────────────────────────────────────────
# 4.  Turing model
# ─────────────────────────────────────────────────────────────────────────────

@model function wheatear_abundance(
    L, U, obs_type, site_idx, year_idx, doy_z,
    n_sites, n_years, N
)
    # ── Fixed effects ─────────────────────────────────────────────────────────
    μ  ~ Normal(log(3.0), 1.5)     # global intercept (log scale); prior near 3 birds
    β₁ ~ Normal(0.0, 1.0)          # linear seasonal effect (standardised DOY)
    β₂ ~ Normal(0.0, 1.0)          # quadratic seasonal effect (unimodal migration curve)

    # ── Random-effect scales (half-normal via Exponential(1) prior) ───────────
    σ_α ~ Exponential(1.0)         # site-level SD
    σ_γ ~ Exponential(1.0)         # year-level SD

    # ── Non-centred random effects ────────────────────────────────────────────
    α_raw ~ filldist(Normal(0.0, 1.0), n_sites)
    γ_raw ~ filldist(Normal(0.0, 1.0), n_years)

    α = σ_α .* α_raw               # site random effects
    γ = σ_γ .* γ_raw               # year random effects

    # ── Observation likelihood ────────────────────────────────────────────────
    for i in 1:N
        log_λ = μ +
                α[site_idx[i]] +
                γ[year_idx[i]] +
                β₁ * doy_z[i]  +
                β₂ * doy_z[i]^2
        λ = exp(log_λ)

        if obs_type[i] == 1
            # Exact count: PMF
            Turing.@addlogprob! poisson_logpmf(λ, L[i])

        elseif obs_type[i] == 2
            # Right-censored ("6+", "present"): 1 − CDF(L[i])
            Turing.@addlogprob! log_rightcensored(λ, L[i])

        else
            # Interval-censored ("c20", "100–150"): CDF(U[i]) − CDF(L[i])
            Turing.@addlogprob! log_interval(λ, L[i], U[i])
        end
    end
end

# ─────────────────────────────────────────────────────────────────────────────
# 5.  Instantiate and sample
# ─────────────────────────────────────────────────────────────────────────────

model = wheatear_abundance(
    L_obs, U_obs, type_obs, site_idx, year_idx, doy_z,
    n_sites, n_years, N
)

# Recommended: start Julia with -t auto for multi-threaded chains
# e.g.  julia -t auto --project=. scripts/wheatear_abundance.jl
n_samples = 1_000
n_adapts  = 500
n_chains  = 4

@info "Sampling with NUTS ($n_chains chains × $n_samples draws + $n_adapts warm-up)…"
chain = sample(
    model,
    NUTS(n_adapts, 0.8),
    MCMCThreads(),
    n_samples,
    n_chains;
    progress = true
)

# ─────────────────────────────────────────────────────────────────────────────
# 6.  Diagnostics
# ─────────────────────────────────────────────────────────────────────────────

println("\n=== Posterior summary (global parameters) ===")
display(summarystats(chain[[:μ, :β₁, :β₂, :σ_α, :σ_γ]]))

# Trace + density plots for global parameters
fig = Figure(size = (1400, 700))
params = [:μ, :β₁, :β₂, :σ_α, :σ_γ]
labels = ["μ (intercept)", "β₁ (DOY linear)", "β₂ (DOY quadratic)",
          "σ_α (site SD)", "σ_γ (year SD)"]

for (j, (p, lab)) in enumerate(zip(params, labels))
    ax = Axis(fig[1, j]; title = lab, xlabel = "Iteration", ylabel = "Value")
    for c in 1:n_chains
        lines!(ax, chain[p][:, 1, c]; linewidth = 0.6)
    end
end
mkpath(plotsdir())
trace_path = plotsdir("wheatear_abundance_traces.png")
save(trace_path, fig)
println("Trace plots → $trace_path")

# Year random effects: recover posterior mean abundance per year
γ_post = [mean(chain["γ_raw[$i]"]) * mean(chain[:σ_γ]) for i in 1:n_years]
fig2 = Figure(size = (800, 400))
ax2  = Axis(fig2[1, 1];
            title  = "Year random effects (posterior mean)",
            xlabel = "Year",
            ylabel = "γ (log scale)")
lines!(ax2, yrs, γ_post; color = :steelblue, linewidth = 2)
scatter!(ax2, yrs, γ_post; color = :steelblue)
year_path = plotsdir("wheatear_year_effects.png")
save(year_path, fig2)
println("Year-effects plot → $year_path")

# ─────────────────────────────────────────────────────────────────────────────
# 7.  Save chain
# ─────────────────────────────────────────────────────────────────────────────

mkpath(datadir("sims"))
chain_path = datadir("sims", "wheatear_abundance_chain.jls")
serialize(chain_path, chain)
println("Chain serialised → $chain_path")
println("Reload with:  chain = deserialize(\"$chain_path\")")
