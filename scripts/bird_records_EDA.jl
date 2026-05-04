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
using DataFramesMeta, CSV, Dates, Random
using Parquet2: writefile, readfile
using Proj

# Initial load and data cleaning. We will do more cleaning later, but this is to get a sense of the data and how to work with it.
birds = CSV.read(datadir("exp_raw", "ABC_2000_2022.csv"), DataFrame;
    normalizenames=true,
    types=Dict(:Date => String, :Date_To => String, :BOU_Order => Float64),
    ignoreemptyrows=true,
    missingstring=["", "#N/A"])

# Drop unneeded columns. Date_to is mostly missing anyway, and sometimes doesn't match Date
select!(birds, Not([:Column14, :Column15, :Sensitive, :Date_To]))

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

@rtransform!(birds, :Date = convertdate(:Date))

CSV.write(datadir("exp_pro", "ABC_2000_2022.csv"), birds)

dropmissing!(birds, [:Species, :Date, :Count])
sort!(birds, :Date)
describe(birds)

# strangely, there are a few observations from 1992, even though the file says it is from 2000
# Drop unneeded columns. Date_to is mostly missing anyway, and sometimes doesn't match Date
#select!(birds, [:Species, :Latin, :Date, :Gridref, :Place, :Count])


"""
    convert_grdref()
    takes a grid reference in the OSGB36 format and converts it to WGS84 latitude and longitude.    
    In theory CoorRefSystems and CoordGridTransforms should be able to do this, but I couldn't get it working, so I wrote my own parser and converter using Proj.jl. 
    The parser is based on the OSGB36 grid reference system, which uses a combination of letters and numbers to specify locations in Great Britain.
"""
function convert_gridref(gridref)

    function parse_osgb36_gridref(gridref::AbstractString)
        gridref = uppercase(strip(gridref))
        # Validate format: two letters followed by even number of digits (at least 2 per coord)
        if !occursin(r"^[A-Z]{2}\d{4,10}$", gridref)
            error("Invalid grid reference format: $gridref")
        end
        # Letter pair to 100km grid square
        letters = "ABCDEFGHJKLMNOPQRSTUVWXYZ"
        l1 = findfirst(==(gridref[1]), letters) - 1
        l2 = findfirst(==(gridref[2]), letters) - 1
        e100km = ((l1 - 2) % 5) * 5 + (l2 % 5)
        n100km = (19 - div(l1, 5) * 5) - div(l2, 5)
        # Remaining digits
        digits = gridref[3:end]
        len = Int(floor(length(digits) / 2))
        e = parse(Int, digits[1:len]) * 10^(5 - len)
        n = parse(Int, digits[len+1:end]) * 10^(5 - len)
        easting = e100km * 100_000 + e
        northing = n100km * 100_000 + n
        return (easting, northing)
    end

    const osgb36 = Proj.CRS("EPSG:27700")
    const wgs84 = Proj.CRS("EPSG:4326")

    if ismissing(gridref)
        return missing
    end
    try
        easting, northing = parse_osgb36_gridref(gridref)
        trans = Proj.Transformation(osgb36, wgs84)
        result = trans(easting, northing)
        # result is (lon, lat)
        return result
    catch e
        println("Bad gridref: $gridref ($e)")
        return missing
    end
end

@rtransform!(birds, :Coordinates = convert_gridref(:Gridref))
dropmissing!(birds, :Coordinates)
@rtransform!(birds, :Latitude = first(:Coordinates), :Longitude = last(:Coordinates))
select!(birds, Not(:Coordinates))
# There are six records with bad grid refs, which we will drop for now. We could try to fix them later, but they are a small proportion of the data.

""" 
    Convert the counts to two columns, L and U. For specific numbers, L = U = that number. For 'present', L = 1 and U = missing. 
    For 'c20', L = 20 and U = missing. For '6+', L = 6 and U = missing. For 50-70 L = 50 and U = 70. For 50-70 
"""
function parse_count(count)
    if ismissing(count)
        return (missing, missing)
    end
    str = lowercase(strip(string(count)))
    if str == "present"
        return (1, 10_000) # we don't know how many, but we can set an upper bound for modelling purposes
    elseif startswith(str, "c")
        try
            num = parse(Int, strip(str[2:end]))
            return (num, 10_000) # we don't know how many more, but we can set an upper bound for modelling purposes
        catch e
            println("Bad count format: $count")
            return (missing, missing)
        end
    elseif endswith(str, "+")
        try
            num = parse(Int, strip(str[1:end-1]))
            return (num, 10_000) # we don't know how many more, but we can set an upper bound for modelling purposes
        catch e
            println("Bad count format: $count")
            return (missing, missing)
        end
    elseif occursin("-", str)
        parts = split(str, "-")
        if length(parts) == 2
            try
                l = parse(Int, strip(parts[1]))
                u = parse(Int, strip(parts[2]))
                return (l, u)
            catch e
                println("Bad count format: $count")
                return (missing, missing)
            end
        else
            println("Bad count format: $count")
            return (missing, missing)
        end
    else
        try
            num = parse(Int, str)
            return (num, num)
        catch e
            println("Bad count format: $count")
            return (missing, missing)
        end
    end
end

@rtransform!(birds, :L = parse_count(:Count)[1], :U = parse_count(:Count)[2])
dropmissing!(birds, [:L, :U])

parse_count("present")
parse_count("c20") # Is this reasonable, or shouw we take, say, +- 20% of the count as the lower/upper bound?
parse_count("6+")
parse_count("50-70")

writefile(datadir("exp_pro", "birds.parquet"), birds)

# Read from here if we have already done the initial cleaning
dataset = readfile(datadir("exp_pro", "birds.parquet"))
birds = DataFrame(dataset)

"""
    Write out separate files for each species of interest. We will focus on a few species for the modelling, but we can always come back and look at others later.
"""
function subset_species(bird_df, species)
    ourspecies = @rsubset(bird_df, :Species == species)
    CSV.write(datadir("exp_pro", "$species.csv"), ourspecies)
    writefile(datadir("exp_pro", "$species.parquet"), ourspecies)
    return ourspecies
end


wheatear = subset_species(birds, "Wheatear")
stonechat = subset_species(birds, "Stonechat")

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

