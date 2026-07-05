@testset "Example garmin-ftms profile" begin
    path = joinpath(@__DIR__, "..", "profiles", "garmin-ftms.toml")
    @test isfile(path)
    rs = Squelch.load_ruleset(path)
    @test rs.device_name == "garmin-ftms"
    @test rs.baud == 115200
    @test !isempty(rs.rules)

    state = Squelch.MonitorState(rs)
    Squelch.process_line!(state, "{\"cmd\":\"status\",\"connected\":true}")
    @test haskey(state.variables, "connected")
end
