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
    job(_->nothing, :f, ("a.exe", "b.exe"))
    rule(_->nothing, "%.exe", "%.o")
    rule(_->nothing, ("%.o", "%.mod"), "%.F90")

    internals[:resolve_all](Set())
    @test internals[:name_graph] == [:default=>Set(:a, :b),
                                     :a=>Set(:c),
                                     :c=>Set(),
                                     :b=>Set(:e, :f),
                                     :e=>Set(),
                                     :f=>Set("a.exe", "b.exe"),
                                     "a.exe"=>Set("a.o"),
                                     "b.exe"=>Set("b.o"),
                                     "a.o"=>Set("a.F90"),
                                     "b.o"=>Set("b.F90"),
                                     "a.F90"=>Set(),
                                     "b.F90"=>Set(),
                                     ]
end
