using Base.Test: @test, @test_throws

using Juke


function graph_of_job_of_target(job_of_target::Dict)
    ret = Dict()
    for (target, j) in job_of_target
        ret[target] = j.ds
    end
    ret
end


let
    c = Juke.Cons(3, Juke.ConsNull())
    @assert !(:a in c)
    c = Juke.Cons(:a, c)
    @assert 3 in c
end

let
    __juke_dsl__= Juke.make_dsl()
    finish = __juke_dsl__[:finish]
    job = __juke_dsl__[:job]
    desc = __juke_dsl__[:desc]
    internals = __juke_dsl__[:internals]
    job(j->nothing, :default, "not_exist.html")
end

let
    __juke_dsl__= Juke.make_dsl()
    finish = __juke_dsl__[:finish]
    job = __juke_dsl__[:job]
    desc = __juke_dsl__[:desc]
    internals = __juke_dsl__[:internals]

    job(:default, "c.exe")
    job(:default, "e.exe")
    job(j->nothing, ["d.exe", "c.exe", "e.exe"], "c.o")

    @test graph_of_job_of_target(
        Juke.collect_phonies!(
            internals[:job_of_target],
            internals[:deps_of_phony],
            internals[:f_of_phony],
        ),
    ) == Dict(
        :default => ["c.exe", "e.exe"],
        "c.exe" => ["c.o"],
        "d.exe" => ["c.o"],
        "e.exe" => ["c.o"],
    )
end
