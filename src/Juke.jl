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

type JobInfo
    name::JobName
    deps::Set{JobName}
end

type PrefixSuffix
    prefix::String
    suffix::String
end

function new_dsl()
    # Environment
    name_graph = Dict{JobName, Set{JobName}}()
    name_to_job = Dict{JobName, Job}()
    rules = Set{(Function, Function, Function)}()
    rules_regex = Set{Regex}()
    rules_prefix_suffix = Set{PrefixSuffix}()

    # DSL
    job(name::Symbol, dep::JobName) = job(name, (dep,))
    job(name::Symbol, deps) = job(_->nothing, name, deps)
    job(name::String, deps) = error("File job $(str(name)) should have command")
    job(command::Function, name::JobName) = job(command, name, ())
    job(command::Function, names) = job(command, names, ())
    job(command::Function, name::JobName, dep::JobName) = job(command, name, (dep,))
    function job(command::Function, name::String, deps)
        for dep in deps
            if isa(dep, Symbol)
                error("File job $(str(name)) should not depend on a command job $(str(dep)) in $(str(deps))")
            end
        end
        _job(command, name, deps)
    end
    job(command::Function, name::Symbol, deps) = _job(command, name, deps)
    job(command::Function, names, deps) = for name in names
        if isa(name, Symbol)
            error("Command job is not allowed in a multiple job declaration")
        end
        job(command, name, deps)
    end

    function _job(command::Function, name::JobName, deps)
        if haskey(name_graph, name)
            error("Overriding job declarations for $(str(name))")
        end
        name_to_job[name] = Job(command, name)
        name_graph[name] = Set{JobName}(deps...)
    end

    rule(command::Function, match_fn::Function, deps_fn::Function) =
        push!(rules, (command, match_fn, name->ensure_set(deps_fn(name))))
    function rule(command, r::Regex, deps_fn::Function)
        if r in rules_regex
            error("Overriding rule declarations for $(str(r))")
        end
        push!(rules_regex, r)
        rule(command, name->(match(r, name) !== nothing), name->deps_fn(match(r, name)))
    end
    function rule(command, prefix_suffix::PrefixSuffix, deps_fn::Function)
        if prefix_suffix in rules_prefix_suffix
            error("Overriding rule declarations for $(str(prefix_suffix))")
        end
        push!(rules_prefix_suffix, prefix_suffix)
        prefix = prefix_suffix.prefix
        suffix = prefix_suffix.suffix
        len_prefix = length(prefix)
        len_suffix = length(suffix)
        rule(command, name->beginswith(name, prefix) && endswith(name, suffix),
             name->deps_fn(name[len_prefix:end-len_suffix]))
    end
    rule(command, prefix_suffix::PrefixSuffix, dep_prefix_suffix::PrefixSuffix) =
        rule(command, prefix_suffix, (dep_prefix_suffix,))
    rule(command, prefix_suffix::PrefixSuffix, dep::String) =
        rule(command, prefixsuffix, get_prefix_suffix(dep))
    rule(command, prefix_suffix::PrefixSuffix, deps_prefix_suffix) =
        rule(command, prefix_suffix, stem->map(d_p_s->"$(d_p_s.prefix)$stem$(d_p_s.suffix)",
                                               deps_prefix_suffix))
    rule(command, name::String, dep::String) = rule(command, name, (dep,))
    rule(command, name::String, deps) = rule(command, get_prefix_suffix(name), map(get_prefix_suffix, deps))

    finish() = finish(:default)
    finish(name::JobName) = finish((name,))
    finish(names) = _finish(names)

    function _finish(names)
        resolve_all(names)
        finish_recur(names)
    end

    function resolve_all(invoked_names)
        undeclared_job_names = setdiff(union(union(values(name_graph)...),
                                             Set{JobName}(invoked_names...)),
                                       Set{JobName}(keys(name_graph)...))

        for name in undeclared_job_names
            if isa(name, Symbol)
                error("Undeclared command job: $(str(name))")
            end

            if ispath(name)
                job(j->error("No command to create $(str(j.name))"), name, ())
            else
                found, new_name_graph, new_name_to_job = resolve(name, rules, Set{JobName}(keys(name_to_job)...))
                if found
                    for (new_name, deps) in new_name_graph
                        job(new_name_to_job[new_name], new_name, deps)
                    end
                else
                    error("Not exist and no job or rule for $(str(name))")
                end
            end
        end
    end

    function finish_recur(name::JobName)
        j = name_to_job[name]
        if !j.done
            j.done = true
            deps = name_graph[name]
            for dep in deps
                finish_recur(dep)
            end

            if need_update(name, deps)
                j.command(JobInfo(name, deps))
            end
        end
    end
    finish_recur(names) = for name in names
        finish_recur(name)
    end

    # Export
    finish, job, rule
end

function resolve(name::String, rules::Set{(Function, Function, Function)},
                 goals::Set{JobName}, parent_names=Set{JobName}())
    if name in parent_names
        return false, Dict{JobName, Set{JobName}}(), Dict{JobName, Function}()
    end
    if name in goals
        return true, Dict{JobName, Set{JobName}}(), Dict{JobName, Function}()
    end

    new_parent_names = union(parent_names, name)
    for (command, match_fn, deps_fn) in rules
        if match_fn(name)
            deps = deps_fn(name)
            new_name_graph = [name=>deps]
            new_name_to_command = [name=>command]
            new_goals = copy(goals)
            ok = true
            for dep in deps
                ok_, n_n_g, n_n_t_c = resolve(dep, rules, new_goals,
                                              new_parent_names)
                if ok_
                    merge!(new_name_graph, n_n_g)
                    merge!(new_name_to_command, n_n_t_c)
                    union!(new_goals, Set(keys(n_n_t_c)...))
                else
                    ok = false
                    break
                end
            end
            if ok
                return true, new_name_graph, new_name_to_command
            end
        end
    end
    false, Dict{JobName, Set{JobName}}(), Dict{JobName, Function}()
end

function get_prefix_suffix(s)
    prefix_suffix = split(s, '%')
    if !(length(prefix_suffix) == 2)
        error("Multiple stem is not allowed: $(str(s))")
    end
    PrefixSuffix(prefix_suffix...)
end

ensure_set(x::JobName) = Set{JobName}(x)
ensure_set(xs) = Set{JobName}(xs...)

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
