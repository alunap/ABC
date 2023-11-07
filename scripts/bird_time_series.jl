#=
Plot the number of birds seen over time by date and look at time series.
=#
using DrWatson
@quickactivate "ABC"
using DataFramesMeta, CSV
using Makie

birds = CSV.read(datadir("exp_raw", "ABC_2000_2022.csv"), DataFrame; normalizenames=true, dateformat="dd/mm/yyyy", types=Dict(:Date => CSV.Date), ignoreemptyrows=true)
birds[!, Not([:Column14, :Column15])]
dropmissing!(birds, :Species)
sort!(birds, :Date)
describe(birds[!, [:Species, :Latin, :Date, :Gridref, :Count]])