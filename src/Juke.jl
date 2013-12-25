module Juke

macro p(ex)
    :(println($(string(ex)), ":\n", $ex, "\n"))
end

type Error <: Exception
    msg::String
end
error(s::String) = throw(Error(s))
error(s...) = error(string(s...))
Base.showerror(io::IO, e::Error) = print(io, e.msg)

typealias JobName Union(String, Symbol)

type Job
    command::Function
    name::JobName
    done::Bool
end
Job(command, name) = Job(command, name, false)
Job(name::String) = Job(_->error("No command to create $(str(name))"), name)
Job(name::Symbol) = Job(_->nothing, name)

type JobInfo
    name::JobName
    deps::Set{JobName}
end

function new_dsl()
    # Environment
    name_graph = Dict{JobName, Set{JobName}}()
    name_to_job = Dict{JobName, Job}()
    rules = Set{(Function, Function, Function)}()
    rules_regex = Set{Regex}()
    rules_prefix_suffix = Set{(String, String)}()

    # DSL
    job(name::Symbol, dep::JobName) = job(name, (dep,))
    job(name::Symbol, deps) = job(_->nothing, name, deps)
    job(name::String, deps) = error("File job $name should have command")
    job(command::Function, name::JobName) = job(command, name, ())
    job(command::Function, names) = job(command, names, ())
    job(command::Function, name::JobName, dep::JobName) = job(command, name, (dep,))
    function job(command::Function, name::String, deps)
        for dep in deps
            if isa(dep, Symbol)
                error("File job $name should not depend on a command job $(str(dep)) in $(str(deps))")
            end
        end
        job_(command, name, deps)
    end
    job(command::Function, name::Symbol, deps) = job_(command, name, deps)
    job(command::Function, names, deps) = for name in names
        if isa(name, Symbol)
            error("Command job is not allowed in a multiple job declaration")
        end
        job(command, name, deps)
    end

    function job_(command::Function, name::JobName, deps)
        if haskey(name_graph, name)
            error("Multiple job declarations for $(str(name))")
        end
        name_to_job[name] = Job(command, name)
        name_graph[name] = Set{JobName}(deps...)
    end

    rule(command::Function, match_fn::Function, deps_fn::Function) =
        push!(rules, (command, match_fn, name->ensure_coll(deps_fn(name))))
    function rule(command, r::Regex, deps_fn::Function)
        if r in rules_regex
            error("Multiple rule declarations for $(str(r))")
        end
        push!(rules_regex, r)
        rule(command, name->(match(r, name) !== nothing), name->deps_fn(match(r, name)))
    end
    function rule(command, prefix_suffix::(String, String), deps_fn::Function)
        if prefix_suffix in rules_prefix_suffix
            error("Multiple rule declarations for $(str(prefix_suffix))")
        end
        push!(rules_prefix_suffix, prefix_suffix)
        prefix, suffix = prefix_suffix
        len_prefix = length(prefix)
        len_suffix = length(suffix)
        rule(command, name->beginswith(name, prefix) && endswith(name, suffix)
             , name->deps_fn(name[len_prefix:end-len_suffix])
             )
    end
    rule(command, prefix_suffix::(String, String), dep_prefix_suffix::(String, String)) =
        rule(command, prefix_suffix, (dep_prefix_suffix,))
    rule(command, prefix_suffix::(String, String), deps_prefix_suffix) =
        rule(command, prefix_suffix, stem->map(d_p_s->"$(d_p_s[1])$stem$(d_p_s[2])"
                                               , deps_prefix_suffix
                                               ))
    rule(command, name::String, dep::String) = rule(command, name, (dep,))
    rule(command, name::String, deps) = rule(command, get_prefix_suffix(name), map(get_prefix_suffix, deps))

    finish(name::String) = finish_(name)
    finish(name::Symbol) = haskey(name_to_job, name) ? finish_(name) : error("$(str(name)) have not declared")
    finish() = finish(:default)

    function finish_(name)
        name_job = get_job(name)
        name_job.done = true

        deps = get_deps(name)
        for dep in deps
            if !get_job(dep).done
                finish_(dep)
            end
        end

        if need_update(name, deps)
            name_job.command(JobInfo(name, deps))
        end
    end

    function make_get_set!(d, inifn)
        k->begin
            if haskey(d, k)
                d[k]
            else
                d[k] = inifn(k)
            end
        end
    end
    get_job = make_get_set!(name_to_job, name->Job(name))
    get_deps = make_get_set!(name_graph, _->Set{JobName}())

    # Export
    finish, job, rule
end

function get_prefix_suffix(s)
    prefix_suffix = split(s, '%')
    if !length(s) == 2
        error("Multiple stem is not allowed: $(str(s))")
    end
    prefix_suffix
end

ensure_coll(x::JobName) = Set{JobName}(x)
ensure_coll(xs) = xs

need_update(name::Number, dep::Number) = name < dep
need_update(name::Symbol, dep::Symbol) = true
need_update(name::Symbol, dep) = true
need_update(name, dep::Symbol) = true
function need_update(name::String, dep::String)
    if ispath(name) && ispath(dep)
        need_update(mtime(name), mtime(dep))
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

str(name::String) = name
str(name::Symbol) = ":$name"
str(x) = repr(x)

end
