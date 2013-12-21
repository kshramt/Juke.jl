module Juke

export new_dsl

macro p(ex)
    :(println($(string(ex)), ":\n", $ex, "\n"))
end

type Error <: Exception
    msg::String
end
error(s::String) = throw(Error(s))
error(s...) = error(string(s...))
Base.showerror(io::IO, e::Error) = print(io, e.msg)

JobName = Union(String, Symbol)

type Job
    command::Function
    name::JobName
    done::Bool
end
Job(command, name) = Job(command, name, false)
Job(name) = Job((_)->nothing, name)

type JobInfo
    name::JobName
    deps::Set{JobName}
end

function new_dsl()
    # Environment
    name_graph = Dict{JobName, Set{JobName}}()
    name_to_job = Dict{JobName, Job}()

    # DSL
    function job(command::Function, name::JobName, deps)
        name_to_job[name] = Job(command, name)
        name_graph[name] = Set{JobName}(deps...)
    end
    job(command::Function, name) = job(command, name, [])
    job(name::JobName, deps) = job((_)->nothing, name, deps)
    job(name) = job(name, [])

    function finish(target::JobName)
        target_job = get_job(target)
        target_job.done = true

        deps = get_deps(target)
        for dep in deps
            if !get_job(dep).done
                finish(dep)
            end
        end

        target_job.command(JobInfo(target, deps))
    end
    finish() = finish(:default)

    # Helper
    function make_get_set!(d, inifn)
        (k)->begin
            if haskey(d, k)
                d[k]
            else
                d[k] = inifn(k)
            end
        end
    end
    get_job = make_get_set!(name_to_job, (name)->Job(name))
    get_deps = make_get_set!(name_graph, (_)->Set{JobName}())

    # Export
    job, finish
end

end
