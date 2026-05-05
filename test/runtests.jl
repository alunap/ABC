using DrWatson, Test
@quickactivate "ABC"
using Proj, Dates
# Here you include files using `srcdir`
include(srcdir("data_utils.jl"))
using .DataUtils

const osgb36 = Proj.CRS("EPSG:27700")
const wgs84 = Proj.CRS("EPSG:4326")
trans = Proj.Transformation(osgb36, wgs84)

# Run test suite
println("Starting tests")
ti = time()

@testset "ABC tests" begin
    @test convertdate("10/10/2022") == Date(2022, 10, 10)
    @test convertdate("2022-10-10") == Date(2022, 10, 10)
    @test convertdate("10/10/10/2022") == Date(2022, 10, 10)
    @test convertdate("2o/03/2022") == Date(2022, 3, 20)
    @test convertdate("2403/2022") == Date(2022, 3, 24)

    @test convert_gridref("NR3589", trans) == (56.0204023764831, -6.254147427715612)
    @test convert_gridref("NM3023", trans) == (56.32220230630327, -6.368640794476017)

    @test parse_count("present") == (1, 10_000, 2)
    @test parse_count("10") == (10, 10, 1)
    @test parse_count("c20") == (16, 24, 3)
    @test parse_count("6+") == (6, 10_000, 2)
    @test parse_count(">6") == (7, 10_000, 2)
    @test parse_count("> 20") == (21, 10_000, 2)
    @test parse_count("50-70") == (50, 70, 3)
    @test ismissing(last(parse_count("hundreds")))
end

ti = time() - ti
println("\nTest took total time of:")
println(round(ti / 60, digits=3), " minutes")
