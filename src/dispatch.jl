mutable struct MonitorState
    ruleset::Ruleset
    log_lines::Vector{String}
    log_capacity::Int
    variables::Dict{String,VariableHistory}
end

function MonitorState(rs::Ruleset; log_capacity::Int=500)
    return MonitorState(rs, String[], log_capacity, Dict{String,VariableHistory}())
end

function process_line!(state::MonitorState, line::AbstractString, t::Float64=time())
    parsed_json = try_parse_json(line)

    for rule in state.ruleset.rules
        value = extract(rule.extractor, line, parsed_json)
        value === nothing && continue
        history = get!(state.variables, rule.name) do
            VariableHistory(rule.name, rule.unit)
        end
        push_value!(history, value, t)
    end

    push!(state.log_lines, String(line))
    while length(state.log_lines) > state.log_capacity
        popfirst!(state.log_lines)
    end
    return nothing
end
