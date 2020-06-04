export get_disk_freespace

# Darwin 64-bit statfs structure
struct darwin_statfs64
    f_bsize::UInt32                     # fundamental file system block size
    f_iosize::Int32                     # optimal transfer block size
    f_blocks::UInt64                    # total data blocks in file system
    f_bfree::UInt64                     # free blocks in fs
    f_bavail::UInt64                    # free blocks avail to non-superuser
    f_files::UInt64                     # total file nodes in file system
    f_ffree::UInt64                     # free file nodes in fs
    f_fsid::NTuple{2,Int32}             # file system id
    f_owner::UInt32                     # user that mounted the filesystem
    f_type::UInt32                      # type of filesystem
    f_flags::UInt32                     # copy of mount exported flags
    f_fssubtype::UInt32                 # fs sub-type (flavor)
    f_fstypename::NTuple{16,Cchar}      # fs type name
    f_mntonname::NTuple{1024,Cchar}     # directory on which mounted
    f_mntfromname::NTuple{1024,Cchar}   # mounted filesystem
    f_reserved::NTuple{8,UInt32}        # For future use

    darwin_statfs64() = new(0,0,0,0,0,0,0,ntuple(x->Int32(0),2),0,0,0,0,ntuple(x->Cchar(0),16),ntuple(x->Cchar(0),1024), ntuple(x->Cchar(0),1024), ntuple(x->UInt32(0),8))
end

# Linux 64-bit (large file support enabled) statvfs struct
struct linux_statvfs64
    f_bsize::Culong                     # Filesystem block size
    f_frsize::Culong                    # Fragment size
    f_blocks::UInt64                    # Size of fs in f_frsize units
    f_bfree::UInt64                     # Number of free blocks
    f_bavail::UInt64                    # Number of free blocks for unprivileged users
    f_files::UInt64                     # Number of inodes
    f_ffree::UInt64                     # Number of free inodes
    f_favail::UInt64                    # Number of free inodes for unprivileged users
    f_fsid::Culong                      # Filesystem ID
    f_flag::Culong                      # Mount flags
    f_namemax::Culong                   # Maximum filename length

    linux_statvfs64() = new(0,0,0,0,0,0,0,0,0,0,0)
end


function statfs(path::AbstractString, kernel::Val{:Darwin})
    s = Ref(darwin_statfs64())
    ret = ccall(:statfs64, Cint, (Cstring, Ref{darwin_statfs64}), string(path), s)
    Base.systemerror("statfs64", ret != 0)
    return s[]
end

function statfs(path::AbstractString, kernel::Val{:Linux})
    s = Ref(linux_statvfs64())
    ret = ccall(:statvfs, Cint, (Cstring, Ref{linux_statvfs64}), string(path), s)
    Base.systemerror("statvfs", ret != 0)
    return s[]
end

function statfs(path::AbstractString, kernel::Val)
    error("Unable to statfs() on $(kernel)")
end

"""
    get_disk_freespace(path)

Returns the amount of available disk space within the filesystem that contains the given
path.  Internally uses `statfs()` which is only implemented on Linux and macOS; throws an
error on all other systems.
"""
function get_disk_freespace(path::AbstractString)
    kernel = Val(Sys.KERNEL)
    s = statfs(path, kernel)
    return s.f_bsize * s.f_bavail
end