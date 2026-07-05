struct VariableRule
    name::String
    unit::String
    extractor::Extractor
end

mutable struct Ruleset
    device_name::String
    baud::Int
    rules::Vector{VariableRule}
end

function extractor_to_dict(e::JSONField)
    return Dict{String,Any}("kind" => "json_field", "path" => e.path)
end

function extractor_to_dict(e::RegexCapture)
    return Dict{String,Any}(
        "kind" => "regex_capture",
        "pattern" => e.pattern.pattern,
        "group" => e.group,
    )
end

function extractor_from_dict(d::AbstractDict)
    kind = d["kind"]
    if kind == "json_field"
        return JSONField(Vector{String}(d["path"]))
    elseif kind == "regex_capture"
        return RegexCapture(Regex(d["pattern"]), Int(d["group"]))
    else
        error("Unknown extractor kind: $kind")
    end
end

function to_dict(rs::Ruleset)
    return Dict{String,Any}(
        "device_name" => rs.device_name,
        "baud" => rs.baud,
        "rules" => [
            Dict{String,Any}(
                "name" => r.name,
                "unit" => r.unit,
                "extractor" => extractor_to_dict(r.extractor),
            ) for r in rs.rules
        ],
    )
end

function ruleset_from_dict(d::AbstractDict)
    rules = VariableRule[
        VariableRule(rd["name"], rd["unit"], extractor_from_dict(rd["extractor"]))
        for rd in d["rules"]
    ]
    return Ruleset(d["device_name"], Int(d["baud"]), rules)
end

function profiles_dir()
    dir = joinpath(homedir(), ".config", "squelch", "profiles")
    mkpath(dir)
    return dir
end

function save_ruleset(rs::Ruleset, path::AbstractString)
    open(path, "w") do io
        TOML.print(io, to_dict(rs))
    end
    return nothing
end

function load_ruleset(path::AbstractString)
    d = TOML.parsefile(path)
    return ruleset_from_dict(d)
end
