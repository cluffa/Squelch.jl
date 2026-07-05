abstract type Extractor end

struct JSONField <: Extractor
    path::Vector{String}
end

struct RegexCapture <: Extractor
    pattern::Regex
    group::Int
end

function try_parse_json(line::AbstractString)
    try
        obj = JSON3.read(line)
        return obj isa JSON3.Object ? obj : nothing
    catch
        return nothing
    end
end

function extract(e::JSONField, ::AbstractString, parsed_json)
    parsed_json === nothing && return nothing
    current = parsed_json
    for key in e.path
        (current isa JSON3.Object) || return nothing
        haskey(current, Symbol(key)) || return nothing
        current = current[Symbol(key)]
    end
    return string(current)
end

function extract(e::RegexCapture, line::AbstractString, ::Union{Nothing,JSON3.Object})
    m = match(e.pattern, line)
    m === nothing && return nothing
    e.group > length(m.captures) && return nothing
    cap = m.captures[e.group]
    return cap === nothing ? nothing : String(cap)
end
