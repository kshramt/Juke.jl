import Base.Test: @test, @test_throws

# Just in a case where `Juke` is not in `~/.julia`
unshift!(LOAD_PATH, joinpath(dirname(@__FILE__), "..", "src"))
import Juke

_n = _->nothing

let
    finish, job, rule, internals = Juke.new_dsl()
    job(_n, :default, "not_exist.html")
    rule(_n, "*.html", "*.md")
    @test_throws Juke.Error internals[:resolve_all](Set())
end

let
    finish, job, rule, internals = Juke.new_dsl()

    job(_n, :default, (:a, :b))
    job(_n, :a, :c)
    job(_n, :c)
    job(_n, :b, (:e, :f))
    job(_n, :e)
    job(_n, :f, ("a.exe", "b.exe", "a.exe"))
    rule(_n, "*.exe", "*.o")
    rule(_n, ("*.o", "*.mod", "*.o"), "*.F90")

    internals[:resolve_all](Set())
    @test internals[:name_graph] == Dict(
                                         :default=>[:a, :b],
                                         :a=>[:c],
                                         :c=>[],
                                         :b=>[:e, :f],
                                         :e=>[],
                                         :f=>["a.exe", "b.exe", "a.exe"],
                                         "a.exe"=>["a.o"],
                                         "b.exe"=>["b.o"],
                                         "a.o"=>["a.F90"],
                                         "b.o"=>["b.F90"],
                                         "a.F90"=>[],
                                         "b.F90"=>[],
                                         )
end

let
    finish, job, rule, internals = Juke.new_dsl()

    job(_n, :default, "c.exe")
    job(_n, ("c.exe", "c.exe"), "c.o")

    internals[:resolve_all](Set())
    @test internals[:name_graph] == Dict(
                                         :default=>["c.exe"],
                                         "c.exe"=>["c.o"],
                                         "c.o"=>[],
                                         )
end
