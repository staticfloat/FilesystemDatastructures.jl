export get_disk_freespace

"""
    get_disk_freespace(path)

Returns the amount of available disk space within the filesystem that contains the given
path.  Internally uses `statfs()` which is only implemented on Linux and macOS; throws an
error on all other systems.
"""
get_disk_freespace

# https://github.com/JuliaLang/julia/pull/42248
if isdefined(Base.Filesystem, :diskstat)
    get_disk_freespace(path) = Base.Filesystem.diskstat(path).available
else
    struct StatFS
        ftype::UInt64
        bsize::UInt64
        blocks::UInt64
        bfree::UInt64
        bavail::UInt64
        files::UInt64
        ffree::UInt64
        fspare::NTuple{4, UInt64}
    end

    function statfs(path::AbstractString)
        req = zeros(UInt8, Base._sizeof_uv_fs)
        err = ccall(:uv_fs_statfs, Cint, (Ptr{Cvoid}, Ptr{Cvoid}, Cstring, Ptr{Cvoid}),
                    C_NULL, req, path, C_NULL)
        err < 0 && Base.uv_error("statfs($(repr(path)))", err)
        statfs_ptr = ccall(:jl_uv_fs_t_ptr, Ptr{Nothing}, (Ptr{Cvoid},), req)
        ret = unsafe_load(reinterpret(Ptr{StatFS}, statfs_ptr))
        ccall(:uv_fs_req_cleanup, Cvoid, (Ptr{Cvoid},), req)
        return ret
    end

    function get_disk_freespace(path)
        s = statfs(path)
        return s.bsize * s.bavail
    end
end
