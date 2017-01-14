# Juke

Make in Julia.

## Features

- Parallel execution of external programs (similar to the `-j` flag of GNU Make).
- Keep going unrelated jobs even when some jobs failes (similar to the `-k` flag of GNU Make).

## Usage

```bash
bin/juke -f Jukefile.jl --jobs=8 --keep-going
```

## Similar Julia packages

- [Jake.jl: Rake for Julia](https://github.com/nolta/Jake.jl)
- [Maker.jl: A tool like make for data analysis in Julia](https://github.com/tshort/Maker.jl)
