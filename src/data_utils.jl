module DataUtils
using DrWatson
@quickactivate "ABC"
using Dates
using Proj
using DataFramesMeta, CSV
using Parquet2: writefile

export convertdate, parse_count, convert_gridref, subset_species

"""The date may either be in dd/mm/yyyy or yyyy-mm-dd format.
First drop missing string, then deal with some known bad dates"""
function convertdate(str)
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


"""
    convert_gridref()
    takes a grid reference in the OSGB36 format and converts it to WGS84 latitude and longitude
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
    Convert the counts to two columns, L and U. 
    For specific numbers, L = U = that number. 
    For 'present', L = 1 and U = missing. 
    For 'c20', L = 20 and U = missing. 
    For '6+', L = 6 and U = missing. 
    for '>6', L = 7 and U = missing.
    For 50-70 L = 50 and U = 70. For 50-70 
    Type = 1 for exact counts, 2 for right-censored, 3 for interval-censored. This will allow us to model the counts appropriately later on.
"""
function parse_count(count)
    if ismissing(count)
        return (missing, missing, missing)
    end
    str = lowercase(strip(string(count)))
    if str == "present"
        return (1, 10_000, 2) # we don't know how many, but we can set an upper bound for modelling purposes
    elseif startswith(str, "c")
        try
            num = parse(Int, strip(str[2:end]))
            return (Int(round(0.8 * num)), Int(round(1.2 * num)), 3)
        catch e
            println("Bad count format: $count")
            return (missing, missing, missing)
        end
    elseif startswith(str, ">")
        try
            num = parse(Int, strip(str[2:end]))
            return (num + 1, 10_000, 2)
        catch
            println("Bad count format: $count")
            return (missing, missing, missing)
        end
    elseif endswith(str, "+")
        try
            num = parse(Int, strip(str[1:end-1]))
            return (num, 10_000, 2) # we don't know how many more, but we can set an upper bound for modelling purposes
        catch e
            println("Bad count format: $count")
            return (missing, missing, missing)
        end
    elseif occursin("-", str)
        parts = split(str, "-")
        if length(parts) == 2
            try
                l = parse(Int, strip(parts[1]))
                u = parse(Int, strip(parts[2]))
                return (l, u, 3)
            catch e
                println("Bad count format: $count")
                return (missing, missing, missing)
            end
        else
            println("Bad count format: $count")
            return (missing, missing, missing)
        end
    else
        try
            num = parse(Int, str)
            return (num, num, 1)
        catch e
            println("Bad count format: $count")
            return (missing, missing, missing)
        end
    end
end


"""
    Write out separate files for each species of interest. We will focus on a few species for the modelling, but we can always come back and look at others later.
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