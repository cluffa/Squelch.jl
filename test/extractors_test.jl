@testset "Extractors" begin
    @testset "try_parse_json" begin
        @test Squelch.try_parse_json("{\"cmd\":\"status\",\"connected\":true}") !== nothing
        @test Squelch.try_parse_json("not json") === nothing
        @test Squelch.try_parse_json("I (1234) machine_ftms: CCCD enabled") === nothing
    end

    @testset "JSONField" begin
        obj = Squelch.try_parse_json("{\"cmd\":\"status\",\"speed\":6.4}")
        e = Squelch.JSONField(["speed"])
        @test Squelch.extract(e, "{\"cmd\":\"status\",\"speed\":6.4}", obj) == "6.4"

        e2 = Squelch.JSONField(["missing"])
        @test Squelch.extract(e2, "{\"cmd\":\"status\",\"speed\":6.4}", obj) === nothing
    end

    @testset "JSONField nested path" begin
        line = "{\"cmd\":\"status\",\"machine\":{\"speed\":6.4}}"
        obj = Squelch.try_parse_json(line)
        e = Squelch.JSONField(["machine", "speed"])
        @test Squelch.extract(e, line, obj) == "6.4"
    end

    @testset "RegexCapture" begin
        e = Squelch.RegexCapture(r"gap (\d+\.\d+) s", 1)
        line = "I (1234) machine_ifit: gap 12.3 s — distance reset"
        @test Squelch.extract(e, line, nothing) == "12.3"

        e2 = Squelch.RegexCapture(r"nomatch(\d+)", 1)
        @test Squelch.extract(e2, line, nothing) === nothing
    end

    @testset "RegexCapture applies even when line is JSON" begin
        e = Squelch.RegexCapture(r"\"speed\":(\d+\.\d+)", 1)
        line = "{\"cmd\":\"status\",\"speed\":6.4}"
        obj = Squelch.try_parse_json(line)
        @test Squelch.extract(e, line, obj) == "6.4"
    end
end
