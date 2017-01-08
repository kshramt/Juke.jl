ENV["SHELLOPTS"] = "pipefail:errexit:nounset:noclobber"

job(:default, :test)

job(:test, "test/runtests.jl.done")

job("test/runtests.jl.done", ["test/runtests.jl", "src/Juke.jl"]) do j
    sh(
        """
        cd test
        julia $(basename(j.ds[1]))
        touch $(basename(j.ts[1]))
        """
    )
end
