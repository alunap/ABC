# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

ABC is a **Julia-based scientific research project** focused on **ecological data analysis and bird count statistics**. The project follows the DrWatson.jl workflow for reproducible scientific computing, combining Julia for computational work with R/Stan for Bayesian statistical modeling.

**Key domains**: Ecological statistics, bird count time series analysis, Bayesian modeling, spatial analysis, data processing pipelines

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

# Prior predictive check for bird counts (R)
Rscript scripts/Birdcounts.R

# Spatial mapping of observations (OS grid refs → WGS84) (R)
Rscript scripts/Mappings.R

# Bayesian analysis with rstanarm (R)
Rscript scripts/bayes_analysis.R
```

### Data Processing Workflow
```bash
# The typical workflow processes raw data in data/exp_raw/ to data/exp_pro/
# Scripts automatically use DrWatson's datadir() function for paths

# View data structure
ls data/exp_raw/    # Raw datasets (ABC_2000_2022.csv)
ls data/exp_pro/    # Processed outputs: ABC_2000_2022.csv, bird_counts.parquet,
                    #   birds.parquet, bird_sample.csv, garvellachs.csv
ls data/sims/       # Simulation results (Abundance_model.RData)
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
   - **Julia**: Primary language for data processing, simulations, and time series analysis
   - **R**: Bayesian statistical modeling (rstanarm), spatial mapping (sf), exploratory analysis
   - **Stan**: Custom probabilistic models for bird count data (`scripts/bird_model.stan`)
   - **Python**: Jupyter notebooks for interactive exploration (pandas, plotly, polars)

2. **Data Processing Chain**:
   - Raw bird observation data → Data cleaning and date parsing → Species aggregation → Time series analysis
   - Handles messy real-world data: inconsistent date formats, uncertain counts ("present", "c20", "6+")
   - Outputs both CSV and Parquet formats for interoperability
   - Spatial component: OS Grid References converted to WGS84 lat/long for mapping

3. **Statistical Modeling Focus**:
   - **Hierarchical Bayesian models** for bird counts with location and temporal effects
   - **Prior predictive checking** for model validation
   - **Uncertainty quantification** for different types of observations (exact counts, ranges, presence-only, right-censored "6+")
   - **Occupancy and abundance models** (see `_research/` for experimental implementations)

4. **Ecological Data Specialization**:
   - Species-specific analysis (Garvellachs location focus; species list in `data/exp_pro/garvellachs.csv`)
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
- **Julia statistics**: Turing.jl, StatisticalRethinking, StatsBase, LogExpFunctions, DualNumbers
- **Julia data**: Parquet2 for efficient storage, PythonCall for interop, CondaPkg (minimal — plotly only)
- **Julia other**: GitHub
- **Python (via uv)**: jupyterlab, pandas, polars, plotly, matplotlib
- **R**: tidyverse, rstanarm, rstan, dagitty, sf (spatial), ggplot2

## Important Notes

- **Data paths**: Always use DrWatson's `datadir()`, `srcdir()` functions rather than hardcoded paths
- **Reproducibility**: All Julia scripts should be self-contained and reproducible via `@quickactivate`
- **Mixed languages**: The project integrates Julia, R, and Python — each script is self-contained
- **Real-world data**: Expect and handle messy ecological data with missing values and inconsistent formats
- **Statistical rigor**: Focus on uncertainty quantification and model checking rather than point estimates
- **Turing.jl AD limitation**: Turing's automatic differentiation passes `DualNumbers` internally, but `StatsFuns` gamma methods don't handle dual number parameters for censored Poisson models. Use `rstan` for censored data models instead (see `_research/birdcounttest.jl` for context)
- **Python environment**: Managed by `uv` with `mise` for Python version pinning. `CondaPkg.jl` is retained only for the Julia `PythonCall` interop layer

