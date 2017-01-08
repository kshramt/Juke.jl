import Base.Test: @test, @test_throws

using Juke

_n = _->nothing

let
    finish, job, internals = Juke.new_dsl()
    job(_n, :default, "not_exist.html")
end

let
    finish, job, internals = Juke.new_dsl()

    job(_n, :default, "c.exe")
    job(_n, ["d.exe", "c.exe"], "c.o")

    @test Juke.graph_of_env(internals[:env]) == Dict(
        :default => ["c.exe"],
        "c.exe" => ["c.o"],
        "d.exe" => ["c.o"],
    )
end
