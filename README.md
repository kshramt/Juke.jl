# Juke

Make in Julia.

## Features

- Parallel execution of external programs (similar to the `-j` flag of GNU Make).
- Keep going unrelated jobs even when some jobs failes (similar to the `-k` flag of GNU Make).

## Usage

```bash
bin/juke -f Jukefile.jl --jobs=8 --keep-going
```

The typical form of a `Jukefile.jl` is as follows:

```julia
job(:default, ["target1"])

desc("Run `command` to make target1 and target2 from dep1, dep2 and dep3")
job(["target1", "target2"], ["dep1", "dep2", "dep3"]) do j
    run(`command --targets=$(join(j.ts, ",")) --deps=$(join(j.ds, ","))`)
end
```

## Similar Julia packages

- [Jake.jl: Rake for Julia](https://github.com/nolta/Jake.jl)
- [Maker.jl: A tool like make for data analysis in Julia](https://github.com/tshort/Maker.jl)
