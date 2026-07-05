@testset "Ruleset" begin
    @testset "to_dict / ruleset_from_dict round trip, JSONField" begin
        rs = Squelch.Ruleset("garmin-ftms", 115200, [
            Squelch.VariableRule("speed", "km/h", Squelch.JSONField(["speed"])),
            Squelch.VariableRule("connected", "", Squelch.JSONField(["status", "connected"])),
        ])
        d = Squelch.to_dict(rs)
        rs2 = Squelch.ruleset_from_dict(d)
        @test rs2.device_name == "garmin-ftms"
        @test rs2.baud == 115200
        @test length(rs2.rules) == 2
        @test rs2.rules[1].name == "speed"
        @test rs2.rules[1].unit == "km/h"
        @test rs2.rules[1].extractor isa Squelch.JSONField
        @test rs2.rules[1].extractor.path == ["speed"]
        @test rs2.rules[2].extractor.path == ["status", "connected"]
    end

    @testset "to_dict / ruleset_from_dict round trip, RegexCapture" begin
        rs = Squelch.Ruleset("generic", 9600, [
            Squelch.VariableRule("gap", "s", Squelch.RegexCapture(r"gap (\d+\.\d+) s", 1)),
        ])
        d = Squelch.to_dict(rs)
        rs2 = Squelch.ruleset_from_dict(d)
        @test rs2.rules[1].extractor isa Squelch.RegexCapture
        @test rs2.rules[1].extractor.pattern.pattern == "gap (\\d+\\.\\d+) s"
        @test rs2.rules[1].extractor.group == 1
    end

    @testset "save_ruleset / load_ruleset file round trip" begin
        rs = Squelch.Ruleset("test-device", 115200, [
            Squelch.VariableRule("speed", "km/h", Squelch.JSONField(["speed"])),
        ])
        path = tempname() * ".toml"
        Squelch.save_ruleset(rs, path)
        @test isfile(path)
        rs2 = Squelch.load_ruleset(path)
        @test rs2.device_name == "test-device"
        @test rs2.baud == 115200
        @test rs2.rules[1].name == "speed"
        rm(path)
    end

    @testset "profiles_dir creates directory" begin
        dir = Squelch.profiles_dir()
        @test isdir(dir)
    end
end
