# FilesystemDatastructures.jl

This package collects useful filesystem datastructures.  Currently, it implements only one, the `SizeConstrainedFileCache`.

## `SizeConstrainedFileCache`

The SCFC implements a flexible filesystem cache that can evict entries when a size pressure is applied.  Currently there is built-in support for eviction policies such as Least-Recently-Used (`LRU`) and Least-Frequently-Used (`LFU`), as well as target size policies such as a constant size, or a mandate to keep at least X bytes on disk free.

Example usage:

```julia
using FilesystemDatastructures

root = mktempdir()
scfc = SizeConstrainedFileCache(root, TargetSizeKeepFree(10*1024^3), DiscardLRU())

# Add a new file:
key = "small_file"
filesize = 10*1024
filedata = rand(UInt8, filesize)
path = add!(scfc, key, filesize)
open(path, "w") do io
    write(path, filedata)
end

# Check to see if that file is there (and also increment its usage counters)
@show hit!(scfc, key)

# Delete that file and its usage counters
delete!(scfc, key)

# Show that hit!() now returns false:
@show hit!(scfc, key)
```