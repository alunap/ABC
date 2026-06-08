using DrWatson, Test
@quickactivate "ABC"
using Proj, Dates
# Here you include files using `srcdir`
include(srcdir("data_utils.jl"))
using .DataUtils

trans = Proj.Transformation(osgb36, wgs84)
const uncensored = 1
const right_censored = 2
const interval_censored = 3

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

    @test parse_count("present") == ObsCount(1, 10_000, right_censored)
    @test parse_count("10") == ObsCount(10, 10, uncensored)
    @test parse_count("c20") == ObsCount(16, 24, interval_censored)
    @test parse_count("6+") == ObsCount(6, 10_000, right_censored)
    @test parse_count(">6") == ObsCount(7, 10_000, right_censored)
    @test parse_count("> 20") == ObsCount(21, 10_000, right_censored)
    @test parse_count("50-70") == ObsCount(50, 70, interval_censored)
    @test parse_count("hundreds") == ObsCount(missing, missing, missing)
end

ti = time() - ti
println("\nTest took total time of:")
println(round(ti / 60, digits=3), " minutes")
