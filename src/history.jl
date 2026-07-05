mutable struct VariableHistory
    name::String
    unit::String
    capacity::Int
    values::Vector{Float64}
    timestamps::Vector{Float64}
    latest_raw::String
end

function VariableHistory(name::String, unit::String; capacity::Int=200)
    return VariableHistory(name, unit, capacity, Float64[], Float64[], "")
end

function push_value!(h::VariableHistory, raw::AbstractString, t::Float64=time())
    h.latest_raw = String(raw)
    parsed = tryparse(Float64, raw)
    if parsed !== nothing
        push!(h.values, parsed)
        push!(h.timestamps, t)
        while length(h.values) > h.capacity
            popfirst!(h.values)
            popfirst!(h.timestamps)
        end
    end
    return nothing
end

function latest(h::VariableHistory)
    isempty(h.values) && return nothing
    return h.values[end]
end
