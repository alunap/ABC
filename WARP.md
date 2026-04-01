# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

ABC is a **Julia-based scientific research project** focused on **ecological data analysis and bird count statistics**. The project follows the DrWatson.jl workflow for reproducible scientific computing, combining Julia for computational work with R/Stan for Bayesian statistical modeling.

**Key domains**: Ecological statistics, bird count time series analysis, Bayesian modeling, data processing pipelines

## Common Development Commands

### Environment Setup
```bash
# Activate the Julia project environment
julia --project=.

# Within Julia REPL, instantiate dependencies
julia> using Pkg; Pkg.instantiate()

# Alternative: activate and instantiate from command line
julia --project=. -e "using Pkg; Pkg.instantiate()"
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
# Run the introductory script (demonstrates DrWatson setup)
julia --project=. scripts/intro.jl

# Process bird data time series
julia --project=. scripts/bird_time_series.jl

# Run simulation examples
julia --project=. scripts/simulated_tits.jl
```

### Data Processing Workflow
```bash
# The typical workflow processes raw data in data/exp_raw/ to data/exp_pro/
# Scripts automatically use DrWatson's datadir() function for paths

# View data structure
ls data/exp_raw/    # Raw datasets (ABC_2000_2022.csv)
ls data/exp_pro/    # Processed outputs (cleaned CSV, Parquet files)
ls data/sims/       # Simulation results
```

### Python Environment (via CondaPkg)
```bash
# Python dependencies are managed through CondaPkg.jl
# The environment is automatically set up when importing PythonCall

julia --project=. -e "using PythonCall"  # This installs Python deps if needed
```

## High-Level Architecture

### DrWatson Project Structure
This is a **DrWatson-compliant** scientific project with a standardized layout:
- **`src/`**: Reusable Julia functions and modules
- **`scripts/`**: Analysis scripts that produce results  
- **`data/`**: Raw data (`exp_raw/`), processed data (`exp_pro/`), simulations (`sims/`)
- **`test/`**: Unit tests
- **Project.toml/Manifest.toml**: Julia environment specifications

### Key Components

1. **Multi-language Statistical Pipeline**:
   - **Julia**: Primary language for data processing, simulations, and time series analysis
   - **R**: Bayesian statistical modeling using rstanarm and exploratory analysis
   - **Stan**: Custom probabilistic models for bird count data with uncertainty

2. **Data Processing Chain**:
   - Raw bird observation data → Data cleaning and date parsing → Species aggregation → Time series analysis
   - Handles messy real-world data: inconsistent date formats, uncertain counts ("present", "c20", "6+")
   - Outputs both CSV and Parquet formats for interoperability

3. **Statistical Modeling Focus**:
   - **Hierarchical Bayesian models** for bird counts with location and temporal effects
   - **Prior predictive checking** for model validation
   - **Uncertainty quantification** for different types of observations (precise, ranges, presence-only)

4. **Ecological Data Specialization**:
   - Species-specific analysis (Garvellachs location focus)
   - Environmental covariates (temperature, habitat, effort)
   - Temporal trends and seasonal patterns

### DrWatson Integration Patterns

Every script follows the DrWatson pattern:
```julia
using DrWatson
@quickactivate "ABC"

# Use DrWatson path functions
datadir("exp_raw", "filename.csv")    # for raw data
datadir("exp_pro", "filename.csv")    # for processed data  
srcdir("module.jl")                   # for source files
```

### Key Dependencies
- **Core**: DrWatson, DataFramesMeta, CSV, Distributions
- **Plotting**: Makie/CairoMakie (Julia), ggplot2 (R)
- **Statistics**: Turing.jl (Julia), rstanarm/Stan (R)
- **Data**: Parquet2 for efficient storage, PythonCall for interop
- **Azure**: Follows Azure development best practices when applicable

## Important Notes

- **Data paths**: Always use DrWatson's `datadir()`, `srcdir()` functions rather than hardcoded paths
- **Reproducibility**: All scripts should be self-contained and reproducible via `@quickactivate`
- **Mixed languages**: The project seamlessly integrates Julia, R, and Python - each script is self-contained
- **Real-world data**: Expect and handle messy ecological data with missing values and inconsistent formats
- **Statistical rigor**: Focus on uncertainty quantification and model checking rather than point estimates

