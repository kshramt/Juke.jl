import Base.Test: @test

# Just in a case where `Juke` is not in `~/.julia`
unshift!(LOAD_PATH, joinpath(dirname(@__FILE__), "..", "src"))
import Juke

let
    finish, job, rule, internals = Juke.new_dsl()

    job(_->nothing, :default, (:a, :b))
    job(_->nothing, :a, :c)
    job(_->nothing, :c)
    job(_->nothing, :b, (:e, :f))
    job(_->nothing, :e)
    job(_->nothing, :f, ("a.exe", "b.exe", "a.exe"))
    rule(_->nothing, "*.exe", "*.o")
    rule(_->nothing, ("*.o", "*.mod", "*.o"), "*.F90")

    internals[:resolve_all](Set())
    @test internals[:name_graph] == [:default=>[:a, :b],
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
                                     ]
end

let
    finish, job, rule, internals = Juke.new_dsl()

    job(_->nothing, :default, "c.exe")
    job(_->nothing, ("c.exe", "c.exe"), "c.o")

    internals[:resolve_all](Set())
    @test internals[:name_graph] == [:default=>["c.exe"],
                                     "c.exe"=>["c.o"],
                                     "c.o"=>[],
                                     ]
end
