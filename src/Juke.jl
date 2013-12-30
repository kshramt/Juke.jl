module Juke

import ArgParse

macro p(ex)
    quote
        let ret=$(esc(ex))
            println($(string(ex)), ":\n", ret, "\n")
            ret
        end
    end
end

const JUKEFILE_NAMES = split("Jukefile jukefile Jukefile.jl jukefile.jl")

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
    deps::Array{JobName, 1}
end

type PrefixSuffix
    prefix::String
    suffix::String
end

function sh(cmds::Base.AbstractCmd, args...)
    println(cmds)
    run(cmds, args...)
end

function new_dsl()
    # Environment
    name_graph = empty_name_graph()
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
    job(command::Function, name::Symbol, dep::JobName) = job(command, name, (dep,))
    job(command::Function, name::String, dep::JobName) = job(command, name, (dep,))
    function job(command::Function, name::String, deps)
        for dep in deps
            if isa(dep, Symbol)
                error("File job $(str(name)) should not depend on a command job $(str(dep)) in $(str(deps))")
            end
        end
        _job(command, name, deps)
    end
    job(command::Function, name::Symbol, deps) = _job(command, name, deps)
    job(command::Function, names, deps) = for name in unique(names)
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
        name_graph[name] = JobName[deps...]
    end

    rule(command::Function, match_fn::Function, deps_fn::Function) =
        push!(rules, (command, match_fn, name->ensure_array(deps_fn(name))))
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
             name->deps_fn(name[1+len_prefix:end-len_suffix]))
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
    rule(command, names, dep::String) = rule(command, names, (dep,))
    rule(command, names, deps) = for name in unique(names)
        rule(command, get_prefix_suffix(name), map(get_prefix_suffix, deps))
    end

    finish() = finish(:default)
    finish(name::JobName) = finish((name,))
    finish(names) = _finish(unique(names))

    function _finish(names)
        resolve_all(names)
        finish_recur(names)
    end

    function resolve_all(invoked_names)
        undeclared_job_names = setdiff(union(union(values(name_graph)...),
                                             Set{JobName}(invoked_names...)),
                                       Set{JobName}(keys(name_graph)...))

        if length(undeclared_job_names) == 0
            return nothing
        end

        additional_names = Set{JobName}()
        for name in undeclared_job_names
            if isa(name, Symbol)
                error("Undeclared command job: $(str(name))")
            end

            found, new_name_graph, new_name_to_command = resolve(name, rules, Set{JobName}(keys(name_to_job)...))
            if found
                for (new_name, deps) in new_name_graph
                    job(new_name_to_command[new_name], new_name, deps)
                    union!(additional_names, deps)
                end
            else
                error("No rule for $(str(name))")
            end
        end
        resolve_all(additional_names)
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
    finish, job, rule,
    [:name_graph=>name_graph,
     :name_to_job=>name_to_job,
     :resolve_all=>resolve_all]
end

function resolve(name::String, rules::Set{(Function, Function, Function)},
                 goals::Set{JobName}, parent_names=Set{JobName}())
    if name in parent_names
        return false, empty_name_graph(), empty_name_to_command()
    elseif name in goals
        return true, empty_name_graph(), empty_name_to_command()
    elseif ispath(name)
        return true, [name=>JobName[]], [name=>j->error("No command to create $(str(j.name))")]
    end

    new_parent_names = union(parent_names, Set(name))
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
    false, empty_name_graph(), empty_name_to_command()
end

empty_name_graph() = Dict{JobName, Array{JobName, 1}}()
empty_name_to_command() = Dict{JobName, Function}()

function get_prefix_suffix(s)
    prefix_suffix = split(s, '*')
    if !(length(prefix_suffix) == 2)
        error("Multiple stem is not allowed: $(str(s))")
    end
    PrefixSuffix(prefix_suffix...)
end

ensure_array(x::JobName) = JobName[x]
ensure_array(xs) = JobName[xs...]

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

function parse_args(args)
    aps = ArgParse.ArgParseSettings("Finish jobs in a Jukefile. Command job name should start with ':' (e.g. `juke :test`).")
    ArgParse.@add_arg_table aps begin
        "names"
        help="names of jobs to be finished"
        nargs='*'
    end
    ArgParse.parse_args(args, aps)
end

function parse_names(names)
    ret = JobName[]
    for name in names
        if beginswith(name, ':')
            name = symbol(name[2:])
        end
        push!(ret, name)
    end
    if length(ret) == 0
        push!(ret, :default)
    end
    ret
end

const str = repr

end
