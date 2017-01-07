import Base.Test: @test, @test_throws

# Just in a case where `Juke` is not in `~/.julia`
unshift!(LOAD_PATH, joinpath(dirname(@__FILE__), "..", "src"))
import Juke

_n = _->nothing

let
    finish, job, internals = Juke.new_dsl()
    job(_n, :default, "not_exist.html")
    @test_throws Juke.Error internals[:resolve](Set())
end

let
    finish, job, internals = Juke.new_dsl()

    job(_n, :default, "c.exe")
    job(_n, ("c.exe", "c.exe"), "c.o")

    internals[:resolve](Set())
    @test internals[:name_graph] == Dict(
                                         :default=>["c.exe"],
                                         "c.exe"=>["c.o"],
                                         "c.o"=>[],
                                         )
end
