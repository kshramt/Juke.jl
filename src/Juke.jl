__precompile__()

module Juke

using ArgParse

const JUKEFILE_NAME = "Jukefile.jl"

type Error <: Exception
    msg::AbstractString
end
err(s::AbstractString) = throw(Error(s))
err(s...) = err(string(s...))
Base.showerror(io::IO, e::Error) = print(io, typeof(e), ": ", e.msg)
#showerror(io::IO, e::Error) = print(io, e.msg)

immutable Cons
    hd
    tl
end
immutable ConsNull
end
Base.in(x, c::ConsNull) = false
Base.in(x, c::Cons) = c.hd == x || x in c.tl


type Job{T, D}
    f::Function
    ts::Vector{T} # targets
    ds::Vector{D} # dependencies
    unique_ds::Vector{D} # unique dependencies
    # number of dependencies not ready
    # - 0 if executable
    # - -1 if executed
    n_rest::Int
    visited::Bool

    function Job(f, ts, ds)
        unique_ds = unique(ds)
        new(f, ts, ds, unique_ds, length(unique_ds), false)
    end
end
Job{D}(f::Function, t::Symbol, ds::AbstractVector{D}) = Job{Symbol, D}(f, [t], ds)
Job{S<:AbstractString}(f::Function, ts::AbstractVector{S}, ds::AbstractVector{S}) = Job{S, S}(f, ts, ds)


function cd(f::Function, d::AbstractString)
    info("cd $(d)")
    Base.cd(f, d)
end


function cp(src::AbstractString, dst::AbstractString; remove_destination::Bool=false, follow_symlinks::Bool=false)
    info("cp $src $dst")
    Base.cp(src, dst; remove_destination=false, follow_symlinks=false)
end


function run(cmd::Base.AbstractCmd)
    info("run(", cmd, ")")
    Base.run(cmd)
end


function mv(src, dst::AbstractString; remove_destination::Bool=false)
    info("mv $src $dst")
    Base.mv(src, dst; remove_destination=remove_destination)
end


function rm(path::AbstractString; force::Bool=false, recursive::Bool=false)
    info("rm $path")
    Base.rm(path; force=force, recursive=recursive)
end


function sh(s, exe="bash")
    run(`$exe -c $s`)
end


function print_deps(job_of_target::Dict)
    for (_, j) in job_of_target
        for t in j.ts
            println(label_of(t))
        end
        for d in j.unique_ds
            println('\t', label_of(d))
        end
        println()
    end
end


label_of(name::Symbol) = ":"*string(name)
label_of(name::AbstractString) = name


function print_descs(descriptions::Dict)
    for ts in sort(collect(keys(descriptions)), by=ts->joinpath(sort(map(string, ts))...))
        for t in sort(ts)
            println(repr(t))
        end
        for d in descriptions[ts]
            println('\t', d)
        end
    end
end


function make_dsl()
    # Environment
    job_of_target = Dict()
    f_of_phony = Dict{Symbol, Function}()
    deps_of_phony = Dict{Symbol, AbstractVector}()
    desc_stack = []
    descriptions = Dict{AbstractVector, AbstractVector}()

    # DSL
    desc(s...) = push!(desc_stack, string(s...))

    job{S<:AbstractString}(f::Function, target::S) = file_job(f, [target], S[])
    job{S<:AbstractString}(f::Function, targets::Vector{S}) = file_job(f, targets, S[])
    job(f::Function, target::AbstractString, dep::AbstractString) = file_job(f, [target], [dep])
    job{S<:AbstractString}(f::Function, target::AbstractString, deps::AbstractVector{S}) = file_job(f, [target], deps)
    job{S<:AbstractString}(f::Function, targets::AbstractVector{S}, dep::AbstractString) = file_job(f, targets, [dep])
    job{S<:AbstractString}(f::Function, targets::AbstractVector{S}, deps::AbstractVector{S}) = file_job(f, targets, deps)

    job(target::Symbol) = phony_job(target, Symbol[])
    job(target::Symbol, dep::Union{Symbol, AbstractString}) = phony_job(target, [dep])
    job(target::Symbol, deps::AbstractVector) = phony_job(target, deps)

    job(f::Function, target::Symbol) = phony_job(f, target, Symbol[])
    job(f::Function, target::Symbol, dep::Union{Symbol, AbstractString}) = phony_job(f, target, [dep])
    job(f::Function, target::Symbol, deps::AbstractVector) = phony_job(f, target, deps)

    function file_job{S<:AbstractString}(f::Function, targets::AbstractVector{S}, deps::AbstractVector{S})
        push_descriptions!(descriptions, targets, desc_stack)
        j = Job(f, targets, deps)
        for t in targets
            uniqsetindex!(job_of_target, j, t)
        end
    end

    function phony_job(f::Function, target::Symbol, deps::AbstractVector)
        uniqsetindex!(f_of_phony, f, target)
        phony_job(target, deps)
    end
    function phony_job(target::Symbol, deps::AbstractVector)
        push_descriptions!(descriptions, [target], desc_stack)
        append!(get!(deps_of_phony, target, []), deps)
    end

    function finish(
        targets::AbstractVector,
        keep_going::Bool,
        n_jobs::Integer,
        load_max,
        print_dependencies::Bool,
        print_descriptiosn::Bool,
    )
        @assert n_jobs > 0

        collect_phonies!(job_of_target, deps_of_phony, f_of_phony)
        deps_of_phony = nothing
        f_of_phony = nothing
        if print_dependencies
            print_deps(job_of_target)
        elseif print_descriptiosn
            print_descs(descriptions)
        else
            dependent_jobs = Dict()
            leaf_jobs = []
            for target in targets
                make_graph!(dependent_jobs, leaf_jobs, target, job_of_target, job, ConsNull())
            end
            process_jobs(leaf_jobs, dependent_jobs, keep_going, n_jobs, load_max)
        end
    end

    # Export
    Dict(
        :finish => finish,
        :job => job,
        :desc => desc,
        :internals => Dict(
            :job_of_target => job_of_target,
            :deps_of_phony => deps_of_phony,
            :f_of_phony => f_of_phony,
        ),
    )
end


function push_descriptions!(descriptions, targets, desc_stack)
    if !isempty(desc_stack)
        append!(get!(descriptions, targets, []), desc_stack)
        empty!(desc_stack)
    end
end


function collect_phonies!(job_of_target, deps_of_phony, f_of_phony)
    for (target, deps) in deps_of_phony
        uniqsetindex!(
            job_of_target,
            Job(get(f_of_phony, target, do_nothing), target, deps),
            target,
        )
    end
    job_of_target
end


function make_graph!(dependent_jobs, leaf_jobs, target, job_of_target, make_job, call_chain)
    (target in call_chain) && err("A circular dependency detected: $(repr(target)) for $(repr(call_chain))")
    if !haskey(job_of_target, target)
        if isa(target, AbstractString) && ispath(target)
            make_job([target], String[]) do j
                err("Must not happen: job for leaf node $(repr(target)) called")
            end
        else
            err("No rule to make $(repr(target))")
        end
    end
    j = job_of_target[target]
    j.visited && return
    j.visited = true

    current_call_chain = Cons(target, call_chain)
    for dep in j.unique_ds
        push!(get!(dependent_jobs, dep, []), j)
        make_graph!(dependent_jobs, leaf_jobs, dep, job_of_target, make_job, current_call_chain)
    end
    isempty(j.unique_ds) && push!(leaf_jobs, j)

    dependent_jobs, leaf_jobs
end


 function process_jobs(jobs::AbstractVector, dependent_jobs::Dict, keep_going::Bool, n_jobs::Integer, load_max)
    push_job, wait_all_tasks, defered_errors = make_task_pool(dependent_jobs, keep_going, n_jobs, load_max)
    for j in jobs
        push_job(j)
    end
    wait_all_tasks()
    if length(defered_errors) > 0
        warn("Following errors have thrown during the execution")
        warn()
        for (j, e) in defered_errors
            warn(repr(e))
            warn(j)
            warn()
        end
        err("Execution failed.")
    end
end


function make_task_pool(dependent_jobs, keep_going::Bool, n_jobs_max::Integer, load_max)
    @assert n_jobs_max > 0
    @assert load_max > 0
    stack = []
    tasks = Set{Task}()
    all_tasks = []
    defered_errors = []
    n_running = 0

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

                    # Start executing the job
                    # `Job` is called only once
                    @assert j.n_rest == 0
                    got_error = false
                    if need_update(j)
                        @assert n_running >= 0
                        if isfinite(load_max)
                            while n_running > 0 && Sys.loadavg()[1] > load_max
                                sleep(1.0)
                            end
                        end
                        n_running += 1
                        try
                            j.f(j)
                        catch e
                            got_error = true
                            # Use string interpolation for async output
                            warn("$(repr(e))\t$(j)")
                            rm_targets(j)
                            if keep_going
                                push!(defered_errors, (j, e))
                            else
                                rethrow(e)
                            end
                        end
                        n_running -= 1
                    end
                    # This job was executed
                    j.n_rest = -1
                    if !got_error
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
                end
            finally
                delete!(tasks, current_task())
            end
            push!(tasks, t)
            push!(all_tasks, t)
            schedule(t)
        end
    end

    push_job, wait_all_tasks, defered_errors
end


rm_targets(j::Job{Symbol}) = nothing
function rm_targets{S<:AbstractString}(j::Job{S})
    for t in j.ts
        try
            # should I add `recursive=true`?
            rm(t, force=true)
        end
    end
end


need_update(::Job{Symbol}) = true
function need_update{S<:AbstractString}(j::Job{S})
    dep_stat_list = map(stat, j.unique_ds)
    # dependencies should exist
    @assert all(ispath, dep_stat_list)
    target_stat_list = map(stat, j.ts)
    all(ispath, target_stat_list) || return true
    isempty(dep_stat_list) && return false
    maximum(mtime, dep_stat_list) > minimum(mtime, target_stat_list)
end


const argparse_conf = ArgParse.ArgParseSettings("Execute jobs in $JUKEFILE_NAME. Phony job name should start with ':' (e.g. `juke :test`).")
ArgParse.@add_arg_table argparse_conf begin
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
    range_tester=x->x > 0
    "--keep-going", "-k"
    help="Defer error throws and run as many unaffected jobs as possible"
    action=:store_true
    "--load-average", "-l"
    help="No new job is started if there are other running jobs and the load average is higher than the specified value"
    arg_type=Float64
    default=typemax(Float64)
    range_tester=x->x > 0
    "--print-dependencies", "-P"
    help="Print dependencies, then exit"
    action=:store_true
    "--descriptions", "-D"
    help="Print descriptions, then exit"
    action=:store_true
end


function parse_args(args, prog)
    argparse_conf.prog = prog
    pargs = ArgParse.parse_args(args, argparse_conf)
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


function do_nothing(j)
    nothing
end

end
