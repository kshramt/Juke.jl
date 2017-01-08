using Base.Test: @test, @test_throws

using Juke

let
    c = Juke.Cons(3, Juke.ConsNull())
    @assert !(:a in c)
    c = Juke.Cons(:a, c)
    @assert 3 in c
end

let
    finish, job, internals = Juke.new_dsl()
    job(j->nothing, :default, "not_exist.html")
end

let
    finish, job, internals = Juke.new_dsl()

    job(:default, "c.exe")
    job(:default, "e.exe")
    job(j->nothing, ["d.exe", "c.exe", "e.exe"], "c.o")

    @test Juke.graph_of_job_of_target(
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
