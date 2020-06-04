function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    isdefined(FilesystemDatastructures, Symbol("#13#14")) && precompile(Tuple{getfield(FilesystemDatastructures, Symbol("#13#14")),SizeConstrainedFileCache})
    isdefined(FilesystemDatastructures, Symbol("#15#17")) && precompile(Tuple{getfield(FilesystemDatastructures, Symbol("#15#17")),SizeConstrainedFileCache})
    isdefined(FilesystemDatastructures, Symbol("#19#21")) && precompile(Tuple{getfield(FilesystemDatastructures, Symbol("#19#21")),SizeConstrainedFileCache})
end
