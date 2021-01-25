export NFileCache

"""
    NFileCache <: FileCache

Represents a number-of-files-constrained file cache. Configurable with maximum number of
files in the cache and how to choose which elements to discard.

Example usage:

    # Create cache that keeps maximum 10 files and releases LRU objects
    fc = NFileCache(root, 10, DiscardLRU())

    # Add a new file:
    path = add!(fc, key)
    open(path, "w") do io
        write(path, filedata)
    end

    # Check to see if that file is there (and also increment its usage counters)
    hit!(fc, key)

    # Delete that file
    delete!(fc, key)
"""
mutable struct NFileCache <: FileCache
    # storage root
    root::String

    # Storage leaves
    entries::Dict{String,CacheEntry}
    # Not directly used by this cache but keeping this field lets us reuse much
    # of the code path between caches
    total_size::UInt64

    # maximum number of entires to keep
    max_entries::Int

    # Sorter function, see SizeConstrainedFileCache
    discard_ordering::Function

    function NFileCache(root::AbstractString, max_entries::Integer, discard_ordering::Function)
        fc = new(
            string(root),
            Dict{String,CacheEntry}(),
            UInt64(0),
            max_entries,
            discard_ordering,
        )

        # Always rebuild the cache so that it represents the correct data on-disk
        rebuild!(fc)

        # After rebuilding, immediately run a shrink check:
        n = length(fc.entries)
        if n > max_entries
            shrink!(fc, n - max_entries)
        end

        return fc
    end
end

"""
    add!(fc::NFileCache, key::AbstractString, new_size=0)

Reserves space for a new file within the file cache.
If the number of files exceed the maximum number of entries allowed in the cache
the cache delete a file as governed by the discard ordering.
"""
function add!(fc::NFileCache, key::AbstractString, new_size=0)
    # Remove this key from the cache if it already exists.
    delete!(fc, key)

    if length(fc.entries) == fc.max_entries
        shrink!(fc, 1)
    end

    fc.entries[key] = CacheEntry(new_size, time(), 1)
    fc.total_size += new_size

    # Return the filepath so that users can use this in `open()` or whatever
    path = filepath(fc, key)
    mkpath(dirname(path))
    return path
end

"""
    shrink!(fc::NFileCache, files_to_remove)

Shrinks a file cache by the amount given by discarding files within the file cache,
stopping only when the target has been met or the list of keys to discard is exhausted.
Returns the new total size of the file cache.
"""
function shrink!(fc::NFileCache, files_to_remove::Integer)
    # Sort the keys by the user criterion
    keys_to_discard = fc.discard_ordering(fc)
    # Delete elements until we are under our target size
    for _ in 1:files_to_remove
        delete!(fc, popfirst!(keys_to_discard))
    end
    return fc.total_size
end
