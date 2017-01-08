__precompile__()

module Juke

using ArgParse

const JUKEFILE_NAME = "Jukefile.jl"

type Error <: Exception
    msg::AbstractString
end
err(s::AbstractString) = throw(Error(s))
err(s...) = err(string(s...))
Base.showerror(io::IO, e::Error) = print(io, e.msg)
#showerror(io::IO, e::Error) = print(io, e.msg)

immutable Cons{H}
    hd::H
    tl
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
    # - 0 if forceable
    # - -1 if forced
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


function rm(path::AbstractString; force=false, recursive=false)
    info("rm $path")
    Base.rm(path; force=force, recursive=recursive)
end


function sh(s, exe="bash")
    run(`$exe -c $s`)
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

    function finish(targets::AbstractVector, print_dependencies::Bool, n_jobs::Integer)
        @assert n_jobs > 0
        if print_dependencies
            print_deps(env)
        else
            dependent_jobs = Dict()
            leaf_jobs = []
            for target in targets
                make_graph!(dependent_jobs, leaf_jobs, target, env, job, ConsNull())
            end
            process_jobs(leaf_jobs, dependent_jobs, n_jobs)
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
            make_job([target], String[]) do j
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


function process_jobs(jobs::AbstractVector, dependent_jobs::Dict, n_jobs::Integer)
    push_job, wait_all_tasks = make_task_pool(n_jobs, dependent_jobs)
    for j in jobs
        push_job(j)
    end
    wait_all_tasks()
end


function make_task_pool(n_jobs_max, dependent_jobs)
    stack = []
    tasks = Set{Task}()
    all_tasks = []

    function wait_all_tasks()
        # I was not sure whether it is safe to extend a vector in `for x in v`
        i = 0
        while true
            i += 1
            length(all_tasks) < i && return
            wait(all_tasks[i])
        end
    end

    function push_job(j)
        push!(stack, j)
        if length(tasks) < n_jobs_max
            t = @task try
                # I assume there is no `wait` inside array operation etc...
                while !isempty(stack)
                    j = pop!(stack)
                    yield() # give other tasks a chance to be invoked
                    force(j, dependent_jobs)
                    for t in j.ts
                        # top targets does not have dependent jobs
                        for dj in get!(dependent_jobs, t, [])
                            dj.n_rest -= 1
                            if dj.n_rest == 0
                                push_job(dj)
                            end
                        end
                    end
                end
            finally
                delete!(tasks, current_task())
            end
            push!(tasks, t)
            schedule(t)
            push!(all_tasks, t)
        end
    end

    push_job, wait_all_tasks
end


function force(j, dependent_jobs::Dict)
    # `Job` is called only once
    @assert j.n_rest == 0
    if need_update(j)
        try
            j.f(j)
        catch e
            for t in j.ts
                try
                    # should I add recursive?
                    rm(t, force=true)
                end
            end
            throw(e)
        end
        # aid for `@assert`
    end
    j.n_rest = -1
end


need_update(::Job{Symbol}) = true
function need_update(j)
    dep_stat_list = map(stat, j.ds)
    # dependencies should exist
    @assert all(ispath, dep_stat_list)
    target_stat_list = map(stat, j.ts)
    all(ispath, target_stat_list) || return true
    isempty(dep_stat_list) && return false
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
        "--jobs", "-j"
        help="Number of parallel jobs"
        arg_type=Int
        default=1
        "--print_dependencies", "-P"
        help="print dependencies"
        action=:store_true
    end
    pargs = ArgParse.parse_args(args, aps)
    pargs["targets"] = parse_names(pargs["targets"])
    pargs
end


function parse_names(names)
    ret = []
    for name in names
        if startswith(name, ':')
            name = Symbol(name[2:end])
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
