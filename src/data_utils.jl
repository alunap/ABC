module DataUtils
using DrWatson
@quickactivate "ABC"
using Dates
using Proj
using DataFramesMeta, CSV
using Parquet2: writefile

export convertdate, parse_count, convert_gridref, subset_species, ObsCount, osgb36, wgs84

# Projections
const osgb36 = Proj.CRS("EPSG:27700")
const wgs84 = Proj.CRS("EPSG:4326")

# Date constants
const default_bad_dates = Dict(
    "10/10/10/2022" => "10/10/2022",
    "2o/03/2022" => "20/03/2022",
    "2403/2022" => "24/03/2022",
    "2503/2022" => "25/03/2022",
    "109/05/2022" => "19/05/2022",
    "18.07.22" => "18/07/2022",
    "[May 2021]" => "15/05/2021")
const iso8601_format = DateFormat("yyyy-mm-dd")
const dmy_format = DateFormat("dd/mm/yyyy")

# Censored data constants
const upperlimit = 10_000 # a number beyond reasonable biological limits, used for right-censored counts
const circum_lower = 0.8
const circum_upper = 1.2
const uncensored = 1
const right_censored = 2
const interval_censored = 3
struct ObsCount
    lower_bound::Union{Int,Missing}
    upper_bound::Union{Int,Missing}
    censor_type::Union{Int,Missing}
end

# Functions

"""
    convertdate(str, bad_dates=default_bad_dates)

    convertdate(str, bad_dates)
    Converts a date string to a Date object.
    The date may either be in dd/mm/yyyy or yyyy-mm-dd format.
    First drop missing string, then deal with some known bad dates.
    A default set of bad dates is provided, but you can also pass in your own dictionary of bad dates if you want to handle different ones.
    If the date is still bad after this, return missing and print a warning.
"""
function convertdate(str, bad_dates=default_bad_dates)
    if ismissing(str)
        return missing
    end

    candidate = get(bad_dates, str, str) # convert known problems or return original value
    if occursin("-", candidate)
        format = iso8601_format
    else
        format = dmy_format
    end
    try
        date = Date(candidate, format)
        return date
    catch e
        @warn("Bad date: $str")
        return missing
    end
end

"""
    parse_osgb36_gridref(gridref::AbstractString)

    Parses a grid reference in the OSGB36 format and returns the easting and northing in meters. The OSGB36 grid reference system uses a combination of letters and numbers to specify locations in Great Britain. The first two letters specify a 100km grid square, and the following digits specify the easting and northing within that square. The number of digits must be even, with at least 2 digits for each coordinate.
"""
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
    len = div(length(digits), 2)
    e = parse(Int, digits[1:len]) * 10^(5 - len)
    n = parse(Int, digits[len+1:end]) * 10^(5 - len)
    easting = e100km * 100_000 + e
    northing = n100km * 100_000 + n
    return (easting, northing)
end


"""
    convert_gridref(gridref, trans)

    Takes a grid reference in the OSGB36 format and converts it to WGS84 latitude and longitude
    (or whatever transformation we pass in).    
    In theory CoorRefSystems and CoordGridTransforms should be able to do this, but I couldn't get it working, so I wrote my own parser and converter using Proj.jl. 
    The parser is based on the OSGB36 grid reference system, which uses a combination of letters and numbers to specify locations in Great Britain.
"""
function convert_gridref(gridref, trans)

    if ismissing(gridref)
        return missing
    end
    try
        easting, northing = parse_osgb36_gridref(gridref)
        result = trans(easting, northing)
        # result is (lat, lon)
        return result
    catch e
        println("Bad gridref: $gridref ($e)")
        return missing
    end
end


""" 
    parse_count(count)
    Parses the count column and returns an ObsCount struct with lower_bound, upper_bound, and censor_type.
    For 'present', lower_bound = 1 and upper_bound = upperlimit.
    For 'c20', lower_bound = 16 and upper_bound = 24.  # limits at ±20% of the count
    For '6+', lower_bound = 6 and upper_bound = upperlimit.
    for '>6', lower_bound = 7 and upper_bound = upperlimit.
    For 50-70 lower_bound = 50 and upper_bound = 70.
    censor_type = 1 for exact counts, 2 for right-censored, 3 for interval-censored. 
    This will allow us to model the counts appropriately later on.
"""
function parse_count(count; upperlimit=upperlimit, circum_lower=circum_lower, circum_upper=circum_upper)
    if ismissing(count)
        return ObsCount(missing, missing, missing)
    end
    str = lowercase(strip(string(count)))
    if str == "present"
        return ObsCount(1, upperlimit, right_censored) # we don't know how many, but we can set an upper bound for modelling purposes
    elseif startswith(str, "c")
        try
            num = parse(Int, strip(str[2:end]))
            return ObsCount(Int(round(circum_lower * num)), Int(round(circum_upper * num)), interval_censored)
        catch e
            @warn("Bad count format: $count. $e")
            return ObsCount(missing, missing, missing)
        end
    elseif startswith(str, ">")
        try
            num = parse(Int, strip(str[2:end]))
            return ObsCount(num + 1, upperlimit, right_censored)
        catch
            println("Bad count format: $count")
            return ObsCount(missing, missing, missing)
        end
    elseif endswith(str, "+")
        try
            num = parse(Int, strip(str[1:end-1]))
            return ObsCount(num, upperlimit, right_censored) # we don't know how many more, but we can set an upper bound for modelling purposes
        catch e
            @warn("Bad count format: $count")
            return ObsCount(missing, missing, missing)
        end
    elseif occursin("-", str)
        parts = split(str, "-")
        if length(parts) == 2
            try
                l = parse(Int, strip(parts[1]))
                u = parse(Int, strip(parts[2]))
                return ObsCount(l, u, interval_censored)
            catch e
                println("Bad count format: $count")
                return ObsCount(missing, missing, missing)
            end
        else
            println("Bad count format: $count")
            return ObsCount(missing, missing, missing)
        end
    else
        try
            num = parse(Int, str)
            return ObsCount(num, num, uncensored)
        catch e
            println("Bad count format: $count")
            return ObsCount(missing, missing, missing)
        end
    end
end


"""
    subset_species(bird_df, species, save=false)

    Subset the bird dataframe for a specific species. If save is true, also save the
    subsetted dataframe to a CSV and Parquet file for later use.
"""
function subset_species(bird_df, species, save=false)
    ourspecies = @rsubset(bird_df, :Species == species)
    if save
        CSV.write(datadir("exp_pro", "$species.csv"), ourspecies)
        writefile(datadir("exp_pro", "$species.parquet"), ourspecies)
    end
    return ourspecies
end

end