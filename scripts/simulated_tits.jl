#=
A translation of chapter 4 AHM to check understanding of the code.
This script processes bird observation data, converting dates and filtering species.
=#

using DrWatson
@quickactivate "ABC"
using DataFramesMeta, Distributions, Random
using CairoMakie

m = 267
j = 3
Random.seed!(24)

elev = rand(Uniform(-1, 1), m)
forest = rand(Uniform(-1, 1), m)
wind = reshape(rand(Uniform(-1, 1), m * j), (m, j))
μλ = 2
β₀ = log(μλ)
β₁ = 2
β₂ = 2
β₃ = 1

logλ = β₀ .+ β₁ .* elev .+ β₂ .* forest .+ β₃ .* elev .* forest
λ = exp.(logλ)

# elevation
xs = [exp(β₀ .+ β₁ .* x) for x in range(-1, 1, step=0.01)]
lines(xs)
scatter(elev, λ)

# forest cover
x2s = [exp(β₀ .+ β₂ .* x) for x in range(-1, 1, step=0.01)]
lines(x2s)
scatter(forest, λ)

cov1 = range(-1, 1, length=100)
cov2 = range(-1, 1, length=100)
λmatrix = [undef, (100, 100)]
