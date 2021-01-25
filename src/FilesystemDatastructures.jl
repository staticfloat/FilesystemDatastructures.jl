module FilesystemDatastructures

# Include the code for this package
include("DiskUtils.jl")
include("SizeConstrainedFileCache.jl")
include("NFileCache.jl")


# precompilation
include(joinpath(dirname(@__DIR__), "deps", "precompile.jl"))
if get(ENV, "FILESYSTEMDATASTRUCTURES_GENERATING_PRECOMPILE", nothing) === nothing
    _precompile_()
end
end # module
