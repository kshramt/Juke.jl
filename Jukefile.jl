ENV["SHELLOPTS"] = "pipefail:errexit:nounset:noclobber"

# joinpath
function jp(xs...)
    normpath(joinpath(map(string, xs)...))
end

job(:default)

job(:test, jp("test", "runtests.jl.done"))

job(jp("test", "runtests.jl.done"), [jp("test", "runtests.jl"), jp("src", "Juke.jl")]) do j
    sh(
        """
        cd test
        julia $(basename(j.ds[1]))
        touch $(basename(j.ts[1]))
        """
    )
end

for (name, f) in (
    (
        "desc", j->begin
            run(`$(j.ds[1]) -f $(j.ds[2])`)
            run(`$(j.ds[1]) -f $(j.ds[2]) --print-dependencies`)
            run(`$(j.ds[1]) -f $(j.ds[2]) -P`)
            run(`$(j.ds[1]) -f $(j.ds[2]) --descriptions`)
            run(`$(j.ds[1]) -f $(j.ds[2]) -D`)
            run(`touch $(j.ts[1])`)
        end,
    ),
)
    job(:example, jp("example", "$(name).jl.done"))
    job(f, jp("example", "$(name).jl.done"), [jp("bin", "juke"), jp("example", "$(name).jl"), jp("src", "Juke.jl")])
end
