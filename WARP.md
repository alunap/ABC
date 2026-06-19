# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

ABC is a **Julia-based scientific research project** focused on **ecological data analysis and bird count statistics**. The project follows the DrWatson.jl workflow for reproducible scientific computing, combining Julia for computational work with R/Stan for Bayesian statistical modeling. It also includes a **React web dashboard** for interactive data exploration and a **Julia/Turing hierarchical abundance model** for Wheatear counts with censored observation handling.

**Key domains**: Ecological statistics, bird count time series analysis, Bayesian modeling, spatial analysis, data processing pipelines, web-based data visualization, censored count models

## Common Development Commands

### Julia Environment Setup
```bash
# Activate the Julia project environment
julia --project=.

# Within Julia REPL, instantiate dependencies
julia> using Pkg; Pkg.instantiate()

# Alternative: activate and instantiate from command line
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

### Python Environment (uv + mise)
```bash
# Python version is managed by mise (see mise.toml — currently Python 3.14)
# Dependencies are managed by uv (see pyproject.toml and uv.lock)

# Install Python dependencies
uv sync

# Run JupyterLab
uv run jupyter lab

# Run a Python script
uv run python main.py
```

### R Environment (renv)
```bash
# R dependencies are managed by renv
# Restore R package library
Rscript -e "renv::restore()"
```

### Testing
```bash
# Run the full test suite
julia --project=. test/runtests.jl

# Run tests through Pkg
julia --project=. -e "using Pkg; Pkg.test()"
```

### Running Scripts
```bash
# Process bird data time series (main Julia pipeline)
julia --project=. scripts/bird_time_series.jl

# Run AHM Chapter 4 simulation (blue tits N-mixture model)
julia --project=. scripts/simulated_tits.jl

# Hierarchical Bayesian Wheatear abundance model (Julia/Turing, censored data)
# Run with multi-threaded chains: julia -t auto --project=. scripts/wheatear_abundance.jl
julia --project=. scripts/wheatear_abundance.jl

# Prior predictive check for bird counts (R)
Rscript scripts/Birdcounts.R

# Spatial mapping of observations (OS grid refs → WGS84) (R)
Rscript scripts/Mappings.R

# Bayesian analysis with rstanarm (R)
Rscript scripts/bayes_analysis.R

# Web dashboard (React + Node + PostGIS)
cd web
npm install
npm run dev          # Dev mode: Vite client + Node API (concurrently)
npm run build        # Production build
npm start            # Production server (serves API + built frontend)
# API runs on port 5174; client dev server runs on port 5173 with /api proxy
```

### Data Processing Workflow
```bash
# The typical workflow processes raw data in data/exp_raw/ to data/exp_pro/
# Scripts automatically use DrWatson's datadir() function for paths

# View data structure
ls data/exp_raw/    # Raw datasets (ABC_2000_2022.csv)
ls data/exp_pro/    # Processed outputs: ABC_2000_2022.csv, birds.parquet,
                    #   wheatear.parquet, wheatear.csv, stonechat.parquet, stonechat.csv,
                    #   bird_counts.parquet, bird_sample.csv, garvellachs.csv
ls data/sims/       # Simulation results (Abundance_model.RData, wheatear_abundance_chain.jls)
```

## High-Level Architecture

### DrWatson Project Structure
This is a **DrWatson-compliant** scientific project with a standardized layout:
- **`src/`**: Reusable Julia functions and modules
- **`scripts/`**: Analysis scripts that produce results (Julia and R)
- **`notebooks/`**: Python Jupyter notebooks for exploration (`birds.ipynb`, `log_reg.ipynb`)
- **`_research/`**: Exploratory and experimental code (Julia, R, Stan) — not production-ready
- **`data/`**: Raw data (`exp_raw/`), processed data (`exp_pro/`), simulations (`sims/`)
- **`test/`**: Unit tests
- **`Project.toml/Manifest.toml`**: Julia environment specifications
- **`pyproject.toml/uv.lock`**: Python environment specifications
- **`renv.lock`**: R environment specification

### Key Components

1. **Multi-language Statistical Pipeline**:
   - **Julia**: Primary language for data processing, simulations, time series analysis, and Bayesian modeling (Turing.jl)
   - **R**: Bayesian statistical modeling (rstanarm), spatial mapping (sf), exploratory analysis
   - **Stan**: Custom probabilistic models for bird count data (`scripts/bird_model.stan`)
   - **Python**: Jupyter notebooks for interactive exploration (pandas, plotly, polars)

2. **Web Dashboard (`web/`)**:
   - **React 19 + Vite** frontend with Recharts for interactive charts
   - **Node.js/Express** API with `pg` (PostgreSQL driver) querying a PostGIS `argyll_birds` table
   - **Features**: species/location filters, date range selection, time series (year/month grain), ranked bar charts, SVG location map, recent records table
   - **Censored count handling**: API dynamically builds SQL expressions for `lower`/`upper` bounds, computing imputed mean counts for aggregation
   - **Column aliases**: API auto-detects columns by common aliases (`species`/`common_name`, `gridref`/`grid_reference`, `date`/`observation_date`, etc.)
   - **Database connection**: configured via `.env` (PGHOST, PGPORT, PGDATABASE, PGSCHEMA, PGTABLE, PGPASSWORD, API_PORT)

3. **Wheatear Abundance Model (`scripts/wheatear_abundance.jl`)**:
   - **Julia/Turing** hierarchical Bayesian model with site and year random effects
   - **Handles censored observations**: exact counts (type=1), right-censored "6+"/"present" (type=2), interval-censored "c20" (type=3)
   - **AD-safe Poisson CDF**: avoids `StatsFuns` regularised-gamma (which fails with Turing's DualNumber parameters) by computing log-CDF via `logsumexp` of PMF terms
   - **Non-centred parameterisation** for numerical stability: `α = σ_α .* α_raw`, `γ = σ_γ .* γ_raw`
   - **Seasonal effects**: standardised day-of-year (`doy_z`) with linear and quadratic terms
   - **Outputs**: serialised chain (`data/sims/wheatear_abundance_chain.jls`), trace plots, year-effect plots
   - **Multi-chain sampling**: run with `julia -t auto` for `MCMCThreads()` parallelisation

4. **Data Processing Chain**:
   - Raw bird observation data → Data cleaning and date parsing → Species aggregation → Time series analysis
   - Handles messy real-world data: inconsistent date formats, uncertain counts ("present", "c20", "6+")
   - Outputs both CSV and Parquet formats for interoperability
   - Spatial component: OS Grid References converted to WGS84 lat/long for mapping
   - **Per-species outputs**: `wheatear.parquet`/`wheatear.csv` and `stonechat.parquet`/`stonechat.csv` extracted from the main birds dataset

5. **Statistical Modeling Focus**:
   - **Hierarchical Bayesian models** for bird counts with location and temporal effects
   - **Prior predictive checking** for model validation
   - **Uncertainty quantification** for different types of observations (exact counts, ranges, presence-only, right-censored "6+")
   - **Occupancy and abundance models** (see `_research/` for experimental implementations)
   - **Censored data models**: Poisson with custom log-likelihoods for right-censored and interval-censored observations

6. **Ecological Data Specialization**:
   - Species-specific analysis (Garvellachs location focus; species list in `data/exp_pro/garvellachs.csv`; Wheatear and Stonechat subsets)
   - Environmental covariates (temperature, habitat, effort)
   - Temporal trends and seasonal patterns

### DrWatson Integration Patterns

Every Julia script follows the DrWatson pattern:
```julia
using DrWatson
@quickactivate "ABC"

# Use DrWatson path functions
datadir("exp_raw", "filename.csv")    # for raw data
datadir("exp_pro", "filename.csv")    # for processed data
srcdir("module.jl")                   # for source files
```

### Key Dependencies
- **Julia core**: DrWatson, DataFramesMeta, CSV, Distributions, Chain
- **Julia plotting**: CairoMakie, Makie, Plots, StatsPlots
- **Julia statistics**: Turing.jl, StatisticalRethinking, StatsBase, LogExpFunctions, DualNumbers, MCMCChains
- **Julia data**: Parquet2 for efficient storage, PythonCall for interop, CondaPkg (minimal — plotly only), Proj (OSGB36 → WGS84)
- **Julia other**: GitHub, Serialization
- **Python (via uv)**: jupyterlab, pandas, polars, plotly, matplotlib
- **R**: tidyverse, rstanarm, rstan, dagitty, sf (spatial), ggplot2
- **Web (Node.js/npm)**: React 19, Recharts, Vite, Express, pg, lucide-react, dotenv, cors, concurrently

## Important Notes

- **Data paths**: Always use DrWatson's `datadir()`, `srcdir()` functions rather than hardcoded paths
- **Reproducibility**: All Julia scripts should be self-contained and reproducible via `@quickactivate`
- **Mixed languages**: The project integrates Julia, R, Python, and Node.js — each script is self-contained
- **Real-world data**: Expect and handle messy ecological data with missing values and inconsistent formats
- **Statistical rigor**: Focus on uncertainty quantification and model checking rather than point estimates
- **Turing.jl AD limitation**: Turing's automatic differentiation passes `DualNumbers` internally, but `StatsFuns` gamma methods don't handle dual number parameters for censored Poisson models. The Wheatear model (`scripts/wheatear_abundance.jl`) works around this by computing log-CDF via `logsumexp` of PMF terms instead of calling `logcdf(Poisson, ·)`
- **Python environment**: Managed by `uv` with `mise` for Python version pinning. `CondaPkg.jl` is retained only for the Julia `PythonCall` interop layer
- **Web dashboard database**: The API expects a PostGIS table with bird observation columns. Configure connection via `.env` in `web/` (PGHOST, PGPORT, PGDATABASE, PGSCHEMA, PGTABLE, PGPASSWORD, API_PORT). The API auto-detects column names by aliases and dynamically builds count expressions for censored data
- **Wheatear model execution**: Always run `julia -t auto --project=. scripts/wheatear_abundance.jl` for multi-threaded multi-chain sampling. The model serialises the full MCMC chain to `data/sims/wheatear_abundance_chain.jls` for downstream analysis

