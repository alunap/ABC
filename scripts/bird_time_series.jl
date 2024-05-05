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

birds = CSV.read(datadir("exp_raw", "ABC_2000_2022_dates.txt"), DataFrame; normalizenames=true, dateformat="dd/mm/yyyy", types=Dict(:Date => String, :Date_To => String), ignoreemptyrows=true, missingstring=["", "#N/A"])
birds[!, Not([:Column14, :Column15])]

function convertdate(str)
    """The date may either be in dd/mm/yyyy or yyyy-mm-dd format"""
    if ismissing(str)
        return ""
    end
    if occursin("-", str)
        format = DateFormat("yyyy-mm-dd")
    else
        format = DateFormat("dd/mm/yyyy")
    end

    returnDate(str, format)
end

@rtransform!(birds, :Date = convertdate(:Date), :Date_To = convertdate(:Date_To))

writefile(datadir("exp_pro", "birds.parquet"), birds)

# Generate species list for The Garvellachs
dropmissing!(birds, [:Species, :Place])
garvellachs = @chain birds begin
    @rsubset(occursin("Garvellachs", :Place))
    unique(:Species)
    select([:Species, :Latin, :Place, :Gridref])
end
CSV.write("garvellach.csv", species_list)

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
mute_swan = @rsubset(bird_counts, :Species == "Mute Swan")

# how many species are we dealing with?
unique(birds, :Species)