__precompile__()

module Juke

import ArgParse

const JUKEFILE_NAME = "Jukefile.jl"

type Error <: Exception
    msg::AbstractString
end
error(s::AbstractString) = throw(Error(s))
error(s...) = error(string(s...))
Base.showerror(io::IO, e::Error) = print(io, e.msg)
#showerror(io::IO, e::Error) = print(io, e.msg)

typealias JobName Union{String, Symbol}

type Job
    command::Function
    name::JobName
    done::Bool
end
Job(command, name) = Job(command, name, false)

immutable JobInfo
    name::JobName
    deps::Array{JobName, 1}
end

function cd(f::Function, d::AbstractString)
    info("cd $(d)")
    Base.cd(f, d)
end

function run(cmds::Base.AbstractCmd, args...)
    info(cmds)
    Base.run(cmds, args...)
end

function print_deps(d::Dict)
    for (target, deps) in d
        println(repr(target))
        for dep in deps
            println('\t', repr(dep))
        end
    end
end

function new_dsl()
    # Environment
    name_graph = empty_name_graph()
    name_to_job = Dict{JobName, Job}()

    # DSL
    job(name::Symbol, dep::JobName) = job(name, (dep,))
    job(name::Symbol, deps) = job(_->nothing, name, deps)
    job(name::AbstractString, deps) = error("File job $(repr(name)) should have command")
    job(command::Function, name::Symbol, dep::JobName) = job(command, name, (dep,))
    job(command::Function, name::AbstractString, dep::JobName) = job(command, name, (dep,))
    function job(command::Function, name::AbstractString, deps)
        for dep in deps
            if isa(dep, Symbol)
                error("File job $(repr(name)) should not depend on a command job $(repr(dep)) in $(repr(deps))")
            end
        end
        _job(command, name, deps, name_graph, name_to_job)
    end
    job(command::Function, name::Symbol, deps=()) = _job(command, name, deps, name_graph, name_to_job)
    job(command::Function, names, deps=()) = for name in unique(names)
        if isa(name, Symbol)
            error("Command job is not allowed in a multiple job declaration")
        end
        job(command, name, deps)
    end

    finish(name::JobName=:default, print_dependencies=false) = finish((name,), print_dependencies)
    finish(names, print_dependencies=false) = _finish(
        unique(names),
        print_dependencies,
        job,
        name_graph,
        name_to_job,
    )

    # Export
    finish, job,
    Dict(
         :name_graph=>name_graph,
         :name_to_job=>name_to_job,
         :resolve=>resolve
         )
end


function _finish(names, print_dependencies, job, name_graph, name_to_job)
    resolve(names, job, name_graph)
    if print_dependencies
        print_deps(name_graph)
    else
        for name in names
            finish_recur(name, name_graph, name_to_job)
        end
    end
end


function finish_recur(name::JobName, name_graph, name_to_job)
    j = name_to_job[name]
    if !j.done
        j.done = true
        deps = name_graph[name]
        for dep in deps
            finish_recur(dep, name_graph, name_to_job)
        end

        if need_update(name, deps)
            j.command(JobInfo(name, deps))
        end
    end
end


function _job(
    command::Function,
    name::JobName,
    deps,
    name_graph,
    name_to_job,
)
    if haskey(name_graph, name)
        error("Overriding job declarations for $(repr(name))")
    end
    name_to_job[name] = Job(command, name)
    name_graph[name] = JobName[deps...]
end


function resolve(invoked_names, job, name_graph)
    undeclared_job_names = setdiff(
        union(
            union(values(name_graph)...),
            Set{JobName}(invoked_names),
        ),
        Set{JobName}(keys(name_graph)),
    )
    if length(undeclared_job_names) == 0
        return nothing
    end

    for name in undeclared_job_names
        if isa(name, Symbol)
            error("Undeclared command job: $(repr(name))")
        elseif ispath(name)
            job(name, JobName[]) do j
                error("Must not happen: command for a leaf job $(repr(j.name)) called")
            end
        else
            error("No rule for $(repr(name))")
        end
    end
end


const empty_name_graph = Dict{JobName, Array{JobName, 1}}

need_update(name::Symbol, dep::Symbol) = true
need_update(name::Symbol, dep) = true
need_update(name, dep::Symbol) = true
function need_update(name::AbstractString, dep::AbstractString)
    if ispath(name) && ispath(dep)
        mtime(name) < mtime(dep)
    else
        true
    end
end
function need_update(name, deps)
    if length(deps) == 0
        !ispath(name)
    else
        any(deps) do dep
            need_update(name, dep)
        end
    end
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
    ret = JobName[]
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

end
