#=
Plot the number of birds seen over time by date and look at time series.
There are a number of issues, especially with counts. They are not strictly numerical.
Some just say 'present', but no real indication of how many are present. Others say
'c20' or '6+'. We don't know exactly how many in the first case, but 20 is the estimate.
We don't know how many more than 6, but at least we know there were 6.
=#
using DrWatson
@quickactivate "ABC"
using DataFramesMeta, CSV, Dates
using Parquet2: writefile

birds = CSV.read(datadir("exp_raw", "ABC_2000_2022.csv"), DataFrame;
    normalizenames=true,
    types=Dict(:Date => String, :Date_To => String),
    ignoreemptyrows=true,
    missingstring=["", "#N/A"])
birds[!, Not([:Column14, :Column15])]

function convertdate(str)
    """The date may either be in dd/mm/yyyy or yyyy-mm-dd format.
    First drop missing string, then deal with some known bad dates"""
    if ismissing(str)
        return ""
    end
    d = Dict(
        "10/10/10/2022" => "10/10/2022",
        "2o/03/2022" => "20/03/2022",
        "2403/2022" => "24/03/2022",
        "2503/2022" => "25/03/2022",
        "109/05/2022" => "19/05/2022",
        "18.07.22" => "18/07/2022",
        "[May 2021]" => "15/05/2021")
    candidate = get(d, str, str) # convert known problems or return original value
    if occursin("-", candidate)
        format = DateFormat("yyyy-mm-dd")
    else
        format = DateFormat("dd/mm/yyyy")
    end
    try
        date = Date(candidate, format)
        return date
    catch e
        println("Bad date: $str")
    end
end

@rtransform!(birds, :Date = convertdate(:Date), :Date_To = convertdate(:Date_To))

CSV.write(datadir("exp_pro", "ABC_2000_2022.csv"), birds)
# Generate species list for The Garvellachs
dropmissing!(birds, [:Species, :Place])
garvellachs = @chain birds begin
    @rsubset(occursin("Garvellachs", :Place))
    unique(:Species)
    select([:Species, :Latin, :Place, :Gridref])
end
CSV.write(datadir("exp_pro", "garvellachs.csv"), garvellachs)

dropmissing!(birds, [:Species, :Date, :Count])
sort!(birds, :Date)
describe(birds[!, [:Species, :Latin, :Date, :Gridref, :Count]])

# strangely, there are a few observations from 1992, even though the file says it is from 2000
# Drop unneeded columns. Date_to is mostly missing anyway, and sometimes doesn't match Date
select!(birds, [:Species, :Latin, :Date, :Gridref, :Place, :Count])

# Convert numbers to numerical values
# Leave Present for now, until we make bins, then we can convert (to what?)
@rtransform!(birds, :Count = ifelse(lowercase(:Count) == "present", "1", :Count))
@rtransform!(birds, :Count = tryparse(Int, strip(:Count, ['+', 'c'])))

# the parse could return nothing, rather than missing. 
# We need to convert to missing in order to drop them.
@rtransform!(birds, :Count = ifelse(isnothing(:Count), missing, :Count))
dropmissing!(birds, :Count)
disallowmissing!(birds, :Count)

# Let's group them and count how many of each species we saw each day, 
# where there were any records for that bird
birds_gdf = groupby(birds, [:Species, :Date])
bird_counts = combine(birds_gdf, :Count => sum => :DayCount)

# Make some plots. There are problems loading PlotlyJS because of WebIO
# and Makie doesn't seem to handle date axes, so save and take up
# the next task in Python.
writefile(datadir("exp_pro", "bird_counts.parquet"), bird_counts)
writefile(datadir("exp_pro", "birds.parquet"), birds)

using PythonCall


mute_swan = @rsubset(bird_counts, :Species == "Mute Swan")
dipper = @rsubset(bird_counts, :Species == "Dipper")
kingfisher = @rsubset(bird_counts, :Species == "Kingfisher")

# how many species are we dealing with?
unique(birds, :Species)