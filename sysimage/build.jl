using Pkg

Pkg.activate(@__DIR__)
if !haskey(Pkg.project().dependencies, "Squelch")
    Pkg.develop(path=dirname(@__DIR__))
end
if !haskey(Pkg.project().dependencies, "PackageCompiler")
    Pkg.add("PackageCompiler")
end
Pkg.instantiate()

using PackageCompiler

const EXT = Sys.isapple() ? "dylib" : Sys.iswindows() ? "dll" : "so"
const OUTDIR = joinpath(homedir(), ".julia", "squelch_sysimage")
const SYSIMAGE_PATH = joinpath(OUTDIR, "squelch.$EXT")

mkpath(OUTDIR)

create_sysimage(
    ["Squelch"];
    sysimage_path=SYSIMAGE_PATH,
    project=@__DIR__,
)

println("Sysimage built at: ", SYSIMAGE_PATH)
