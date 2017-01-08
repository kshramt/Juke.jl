__precompile__()

module Juke

import ArgParse

const JUKEFILE_NAME = "Jukefile.jl"

type Error <: Exception
    msg::AbstractString
end
err(s::AbstractString) = throw(Error(s))
err(s...) = err(string(s...))
Base.showerror(io::IO, e::Error) = print(io, e.msg)
#showerror(io::IO, e::Error) = print(io, e.msg)

immutable Cons{H, T}
    hd::H
    tl::T
end
immutable ConsNull
end
cons(hd, tl) = Cons(hd, tl)
Base.in(x, c::ConsNull) = false
Base.in(x, c::Cons) = c.hd == x || x in c.tl


type Job{T, D}
    f::Function
    ts::Vector{T} # targets
    ds::Vector{D} # deps
    # number of dependencies not ready
    # - 0 if invokable
    # - -1 if invoked
    n_rest::Integer
    visited::Bool

    function Job(f, ts, ds)
        @assert length(unique(ds)) == length(ds)
        new(f, ts, ds, length(ds), false)
    end
end
Job(f, ts::Vector{Symbol}, ds::Vector{Symbol}) = Job{Symbol, Symbol}(f, ts ,ds)
Job{S<:AbstractString}(f, ts::Vector{Symbol}, ds::Vector{S}) = Job{Symbol, S}(f, ts ,ds)
Job{S<:AbstractString}(f, ts::Vector{S}, ds::Vector{S}) = Job{S, S}(f, ts ,ds)


function cd(f::Function, d::AbstractString)
    info("cd $(d)")
    Base.cd(f, d)
end


function run(cmds::Base.AbstractCmd, args...)
    info(cmds)
    Base.run(cmds, args...)
end


function print_deps(env::Dict)
    for (target, deps) in graph_of_env(env)
        println(repr(target))
        for dep in deps
            println('\t', repr(dep))
        end
    end
end


function graph_of_env(env::Dict)
    ret = Dict()
    for (target, j) in env
        ret[target] = j.ds
    end
    ret
end


function new_dsl()
    # Environment
    env = Dict()

    # DSL
    job{S<:AbstractString}(f::Function, target::S) = job(f, target, S[])
    job(f::Function, target::AbstractString, dep::AbstractString) = job(f, [target], [dep])
    job(f::Function, target::AbstractString, deps::AbstractVector) = job(f, [target], deps)

    job(target::Symbol, dep::Union{Symbol, AbstractString}) = job(target, [dep])
    job(target::Symbol, deps::AbstractVector) = job(_->nothing, target, deps)

    job{S<:AbstractString}(f::Function, targets::Vector{S}) = job(f, targets, S[])
    job{S<:AbstractString}(f::Function, targets::Vector{S}, dep::AbstractString) = job(f, targets, [dep])

    job(f::Function, target::Symbol) = job(f, target, Symbol[])
    job(f::Function, target::Symbol, dep::Union{Symbol, AbstractString}) = job(f, target, [dep])
    job(f::Function, target::Symbol, deps::AbstractVector) = job(f, [target], deps)

    job(targets::AbstractVector{Symbol}, dep::Union{Symbol, AbstractString}) = job(targets, [dep])
    job(targets::AbstractVector{Symbol}, deps::AbstractVector) = job(_->nothing, targets, deps)

    job(f::Function, targets::AbstractVector{Symbol}) = job(f, targets, Symbol[])
    job(f::Function, targets::AbstractVector{Symbol}, dep::Union{Symbol, AbstractString}) = job(f, targets, [dep])

    function job(f::Function, targets::AbstractVector, deps::AbstractVector)
        j = Job(f, targets, deps)
        for t in targets
            uniqsetindex!(env, j, t)
        end
        j
    end

    function finish(targets::AbstractVector, print_dependencies=false)
        if print_dependencies
            print_deps(env)
        else
            dependent_jobs = Dict()
            leaf_jobs = []
            for target in targets
                make_graph!(dependent_jobs, leaf_jobs, target, env, job, ConsNull())
            end
            force(leaf_jobs, dependent_jobs)
        end
    end

    # Export
    (
        finish,
        job,
        Dict(
            :env => env,
        ),
    )
end


function make_graph!(dependent_jobs, leaf_jobs, target, env, make_job, call_chain)
    @assert !(target in call_chain)
    if !haskey(env, target)
        if isa(target, AbstractString) && ispath(target)
            make_job([target], []) do j
                err("Must not happen: job for leaf node $(repr(target)) called")
            end
        else
            err("No rule to make $(repr(target))")
        end
    end
    j = env[target]
    j.visited && return
    j.visited = true

    current_call_chain = Cons(target, call_chain)
    for dep in j.ds
        push!(get!(dependent_jobs, dep, []), j)
        make_graph!(dependent_jobs, leaf_jobs, dep, env, make_job, current_call_chain)
    end
    isempty(j.ds) && push!(leaf_jobs, j)

    dependent_jobs, leaf_jobs
end


function force(jobs::AbstractVector, dependent_jobs::Dict)
    for j in jobs
        force(j, dependent_jobs)
    end
end
function force(j, dependent_jobs::Dict)
    # `Job` is called only once
    @assert j.n_rest == 0
    if need_update(j)
        j.f(j)
        # aid for `@assert`
        j.n_rest = -1
    end
    for t in j.ts
        for dj in get!(dependent_jobs, t, [])
            dj.n_rest -= 1
        end
    end
    for t in j.ts
        for dj in dependent_jobs[t]
            if dj.n_rest == 0
                force(dj, dependent_jobs)
            end
        end
    end
end


need_update(::Job{Symbol}) = true
function need_update(j)
    dep_stat_list = map(stat, j.ds)
    # dependencies should exist
    @assert all(ispath, dep_stat_list)
    target_stat_list = map(stat, j.ts)
    all(ispath, target_stat_list) || return true
    maximum(mtime, dep_stat_list) > minimum(mtime, target_stat_list)
end


function parse_args(args)
    aps = ArgParse.ArgParseSettings("Finish jobs in a $JUKEFILE_NAME. Command job name should start with ':' (e.g. `juke :test`).")
    ArgParse.@add_arg_table aps begin
        "targets"
        help="names of jobs to be finished"
        nargs='*'
        "--file", "-f"
        help="use FILE as a Juke file"
        arg_type=String
        default=JUKEFILE_NAME
        "--print_dependencies", "-P"
        help="print dependencies"
        action=:store_true
    end
    parsed_args = ArgParse.parse_args(args, aps)
    parsed_args["targets"] = parse_names(parsed_args["targets"])
    parsed_args
end


function parse_names(names)
    ret = []
    for name in names
        if startswith(name, ':')
            name = symbol(name[2:end])
        end
        push!(ret, name)
    end
    if length(ret) == 0
        push!(ret, :default)
    end
    ret
end


function uniqsetindex!(d::Dict, v, k)
    @assert !haskey(d, k)
    d[k] = v
end

end
