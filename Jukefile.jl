job(:default, :test)

job(:test) do j
    cd("test") do
        run(`julia runtests.jl`)
    end
end
