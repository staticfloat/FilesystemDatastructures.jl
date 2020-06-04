function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    isdefined(FilesystemDatastructures, Symbol("#3#4")) && precompile(Tuple{getfield(FilesystemDatastructures, Symbol("#3#4")),SizeConstrainedFileCache})
    isdefined(FilesystemDatastructures, Symbol("#5#7")) && precompile(Tuple{getfield(FilesystemDatastructures, Symbol("#5#7")),SizeConstrainedFileCache})
    isdefined(FilesystemDatastructures, Symbol("#9#11")) && precompile(Tuple{getfield(FilesystemDatastructures, Symbol("#9#11")),SizeConstrainedFileCache})
    precompile(Tuple{Type{SizeConstrainedFileCache},String,Function,Function})
end
