#=
Plot the number of birds seen over time by date and look at time series.
There are a number of issues, especially with counts. They are not strictly numerical.
Some just say 'present', but no real indication of how many are present. Others say
'c20' or '6+'. We don't know exactly how many in the first case, but 20 is the estimate.
We don't know how many more than 6, but at least we know there were 6.

See the distinction between left-censored (e.g. 'present' or '6+') and right-censored (e.g. 'c20') data, and how to model them appropriately. Also the difference between truncated and censored data.
=#
using DrWatson
@quickactivate "ABC"
using DataFramesMeta, CSV, Random, Chain
using Parquet2: writefile, readfile
using Proj
include(srcdir("data_utils.jl"))
using .DataUtils

const osgb36 = Proj.CRS("EPSG:27700")
const wgs84 = Proj.CRS("EPSG:4326")
trans = Proj.Transformation(osgb36, wgs84) # this is expensive, so do it once and reuse it

# Initial load and data cleaning. We will do more cleaning later, but this is to get a sense of the data and how to work with it.
birds = CSV.read(datadir("exp_raw", "ABC_2000_2022.csv"), DataFrame;
    normalizenames=true,
    types=Dict(:Date => String, :Date_To => String, :BOU_Order => Float64),
    ignoreemptyrows=true,
    missingstring=["", "#N/A"])

# Drop unneeded columns. Date_to is mostly missing anyway, and sometimes doesn't match Date
select!(birds, Not([:Column14, :Column15, :Sensitive, :Date_To]))

@rtransform!(birds, :Date = convertdate(:Date))

dropmissing!(birds, [:Species, :Date, :Count])
sort!(birds, :Date)

# strangely, there are a few observations from 1992, even though the file says it is from 2000
# Drop unneeded columns. Date_to is mostly missing anyway, and sometimes doesn't match Date
#select!(birds, [:Species, :Latin, :Date, :Gridref, :Place, :Count])

birds = @chain birds begin
    @rtransform(:Coordinates = convert_gridref(:Gridref, trans))
    dropmissing(:Coordinates)
    @rtransform(:Latitude = first(:Coordinates), :Longitude = last(:Coordinates))
    select(Not(:Coordinates))
end

# There are six records with bad grid refs, which we will drop for now. We could try to fix them later, but they are a small proportion of the data.

# test examples
parse_count("present")
parse_count("10")
parse_count("c20")
parse_count("6+")
parse_count(">6")
parse_count("> 20")
parse_count("50-70")
parse_count("hundreds")# too vague to use in a model
# Some bad counts that may be usable: Y, +, '2 (ringed)', '6 at roost', '2 pair', 
# '11 + 3 juv', 'P', "50 in flock". Split words into the comments.

# Transform the whole dataset
@rtransform!(birds, :L = parse_count(:Count)[1], :U = parse_count(:Count)[2])
dropmissing!(birds, [:L, :U])

writefile(datadir("exp_pro", "birds.parquet"), birds)

# Read from here if we have already done the initial cleaning
dataset = readfile(datadir("exp_pro", "birds.parquet"))
birds = DataFrame(dataset)


wheatear = subset_species(birds, "Wheatear")
stonechat = subset_species(birds, "Stonechat")
CSV.write(datadir("exp_pro", "ABC_2000_2022.csv"), birds)

#--------------------------------------
# how many species are we dealing with?
unique(birds, :Species)

# How many places, and how many observations per place?
unique(birds, :Gridref)
places = groupby(birds, :Gridref)


observers = select(unique(birds, :Observer), :Observer)
maximum(birds.Date) # end of 2022
minimum(birds.Date) # one day in 1992, which is odd given the file name. We will drop this record for now, but we could investigate it later.
early_birds = @rsubset(birds, :Date < Date(2000, 1, 1))
