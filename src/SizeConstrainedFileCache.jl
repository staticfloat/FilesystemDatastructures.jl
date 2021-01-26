export SizeConstrainedFileCache, add!, delete!, hit!, rebuild!, filepath,
       TargetSizeConstant, TargetSizeKeepFree, DiscardLRU, DiscardLFU

struct CacheEntry
    size::UInt64
    last_accessed::Float64
    num_accessed::UInt64
end

abstract type FileCache end

"""
    SizeConstrainedFileCache <: FileCache

Represents a size-constrained file cache.  Configurable with different policies for when
to discard elements from the cache and how to choose which elements to discard.

    SizeConstrainedFileCache(root, target_func, discard_func; predicate=x->true)

Construct a new file cache. Arguments:
 - `root`: the root directory of the cache.
 - `target_func`: function that return the (maximum) number of bytes that files
   in the cache may occupy, see e.g. `TargetSizeKeepFree` and `TargetSizeConstant`.
 - `discard_func`: function that return the eviction order, see e.g. `DiscardLRU`
   and `DiscardLFU`.
 - `predicate`: function that determines whether a file should be tracked/included
   in the cache. Currently only used for existing files when setting up the file cache.
   The default is to track every existing file.

!!! warn
    This is a potentially destructive operation since the file cache may delete
    files in the `root` directory to fit the given constraints.

Example usage:

    # Create cache that keeps 10GB free and releases LRU objects
    scfc = SizeConstrainedFileCache(root, TargetSizeKeepFree(10*1024^3), DiscardLRU())

    # Add a new file:
    path = add!(scfc, key, filesize)
    open(path, "w") do io
        write(path, filedata)
    end

    # Check to see if that file is there (and also increment its usage counters)
    hit!(scfc, key)

    # Delete that file
    delete!(scfc, key)
"""
mutable struct SizeConstrainedFileCache <: FileCache
    # storage root
    root::String

    # Storage leaves
    entries::Dict{String,CacheEntry}
    total_size::UInt64

    # Function that returns the target size of the cache.
    # For simple usage, this can simply return a constant:
    #   (scfc) -> 4*1024*1024*1024
    # For more complex usage, this may return a size that always leaves
    # a certain amount of space free for the rest of the system.
    target_size::Function

    # Function that sorts the cache entries, returning the values that we should
    # drop in order to free up more space.  An example of this is a function that
    # simply sorts by time last accessed:
    #   (entries) -> sort(entries, by = k -> entries[k].last_accessed)
    # For more complex usage, users may wish to sort objects by some combination
    # of how often they are accessed, how recently they were accessed, and the size
    # of the object that may be freed.  Or perhaps ensure that some keys are never
    # discarded, etc...
    discard_ordering::Function

    function SizeConstrainedFileCache(root::AbstractString, target_size::Function, discard_ordering::Function;
                                      predicate::Function=x->true)
        scfc = new(
            string(root),
            Dict{String,CacheEntry}(),
            UInt64(0),
            target_size,
            discard_ordering,
        )

        # Always rebuild the scfc so that it represents the correct data on-disk
        rebuild!(scfc; predicate=predicate)

        # After rebuilding, immediately run a shrink check:
        target_size = scfc.target_size(scfc)
        if scfc.total_size > target_size
            shrink!(scfc, scfc.total_size - target_size)
        end

        # Finally, give the scfc back
        return scfc
    end
end

"""
    filepath(fc::FileCache, key::AbstractString)

Given a `key`, returns the path on disk for that key.
"""
function filepath(scfc::FileCache, key::AbstractString)
    return joinpath(scfc.root, key)
end

"""
    add!(scfc::SizeConstrainedFileCache, key::AbstractString, new_size)

Reserves space for a new file within the file cache of the specified size.  If the
addition would result in a new total size that is greater than the target specified by
the `target_size` function passed to the SCFC constructor, `shrink!()` the file cache
until this new object can fit nicely within the cache without overstepping any file size
bounds.  If the new object cannot fit wihtin the cache at all, throws an `ArgumentError`.

`add!()`'ing an entry that already exists within the file cache overwrites it and clears
all access counters, treating it as a semantically different object than the object that
was replaced.
"""
function add!(scfc::SizeConstrainedFileCache, key::AbstractString, new_size)
    # Remove this key from the cache if it already exists.
    delete!(scfc, key)

    target_size = UInt64(scfc.target_size(scfc))
    new_total_size = UInt64(scfc.total_size + new_size)
    if new_total_size > target_size
        # If the new value is just preposterously large, complain
        if new_size > target_size
            throw(ArgumentError(
                "Requested size $(new_size) is larger than entire cache $(target_size)"
            ))
        end

        # Call `shrink!()``.  We have no behavior for `shrink!()` failing; we assume it
        # can always hit the shrinking target we give it.
        shrink!(scfc, UInt64(new_total_size - target_size))
    end

    scfc.entries[key] = CacheEntry(new_size, time(), 1)
    scfc.total_size += new_size

    # Return the filepath so that users can use this in `open()` or whatever
    path = filepath(scfc, key)
    mkpath(dirname(path))
    return path
end

"""
    delete!(fc::FileCache, key)

Removes a key from the file cache, clearing all metadata about that key within the cache.
Also removes the backing file on disk if it still exists.  Returns `true` if the key was
actually deleted.
"""
function Base.delete!(scfc::FileCache, key::AbstractString)
    if !haskey(scfc.entries, key)
        return false
    end

    entry = scfc.entries[key]
    rm(filepath(scfc, key); force=true)
    delete!(scfc.entries, key)
    scfc.total_size -= entry.size
    return true
end

"""
    hit!(fc::FileCache, key)

Returns `true` if the key exists within the cache, `false` otherwise.  Increments access
counters for the given key, recording last access time, number of times accessed, etc...
"""
function hit!(scfc::FileCache, key::AbstractString)
    # If this is not in our entries, return `false`
    if !haskey(scfc.entries, key)
        return false
    end

    old_entry = scfc.entries[key]
    scfc.entries[key] = CacheEntry(old_entry.size, time(), old_entry.num_accessed + 1)

    # We `touch()` it here, so that if we have to rebuild the cache from disk,
    # our access times are roughly in-line with what we would expect.
    touch(filepath(scfc, key))
    return true
end

"""
    rebuild!(fc::FileCache; predicate::Function = x -> true)

Rebuilds the file cache datastructures within memory from disk.  This is not a lossless
operation; last access times may be inaccurate and number of times accessed will be set
to 1 for any key that was not previously tracked.  This is done automatically when
creating a new cache; the file cache will scan its root directory and populate itself with the
values gathered using this function.

The `predicate` keyword can be used to pass a predicate function (input: `key`, output: `Bool`)
to filter which files in the root directory that should be tracked/included in the cache.
The default is to include every file.
"""
function rebuild!(scfc::FileCache; predicate::Function = x -> true)
    # Clear the total size to zero, then build it back up again
    scfc.total_size = UInt64(0)

    # We will create a new entries dict:
    new_entries = Dict{String,CacheEntry}()
    old_entries = scfc.entries

    # Ensure that the cache root always exists
    mkpath(scfc.root)
    for (parent, dirs, files) in walkdir(scfc.root)
        for fname in files
            path = joinpath(parent, fname)
            key = relpath(path, scfc.root)

            # Check if this file should be included
            if !(predicate(key)::Bool)
                continue
            end

            # First, collect ground-truth size
            st = stat(path)
            size = filesize(st)

            # Default values
            last_accessed = mtime(st)
            num_accessed = 1

            # Next, let's see if this actually existed in the scfc before.  If they did,
            # use the values from the old metadata rather than the defaults above.
            key = relpath(path, scfc.root)
            if haskey(old_entries, key)
                last_accessed = old_entries[key].last_accessed
                num_accessed = old_entries[key].num_accessed
            end

            # Store this new value into `new_entries` and update `total_size`
            new_entries[key] = CacheEntry(size, last_accessed, num_accessed)
            scfc.total_size += size
        end
    end

    # Finally, update `scfc.entries` and let `old_entries` wither
    scfc.entries = new_entries
    return nothing
end

"""
    shrink!(scfc, size_to_shrink)

Shrinks a file cache by the amount given by discarding files within the file cache,
stopping only when the target has been met or the list of keys to discard is exhausted.
Returns the new total size of the file cache.
"""
function shrink!(scfc::SizeConstrainedFileCache, size_to_shrink::UInt64)
    # Sort the keys by the user criterion
    keys_to_discard = scfc.discard_ordering(scfc)

    # Delete elements until we are under our target size
    target_size = scfc.total_size - size_to_shrink
    while scfc.total_size > target_size && !isempty(keys_to_discard)
        delete!(scfc, popfirst!(keys_to_discard))
    end
    return scfc.total_size
end


## Policies for determining target size of the cache:
# Keep cache always below `bytes` size
TargetSizeConstant(bytes) = (scfc) -> UInt64(bytes)
# Ensure that `bytes` are always free on the disk the scfc is stored on
TargetSizeKeepFree(bytes) = (scfc) -> begin
    # Be careful of unsigned wraparound
    curr = get_disk_freespace(scfc.root) + scfc.total_size
    if bytes > curr
        return UInt64(0)
    else
        return UInt64(curr - bytes)
    end
end


## Policies for sorting entries for discard.  We define LRU and LFU here as an example.
DiscardLRU() = (scfc) -> begin
    sort(collect(keys(scfc.entries)); by = k -> scfc.entries[k].last_accessed)
end
# Note that for LFU, we break ties by falling back to discarding the least-recently used:
DiscardLFU() = (scfc) -> begin
    sort(collect(keys(scfc.entries)); by = k -> (scfc.entries[k].num_accessed,
                                                 scfc.entries[k].last_accessed))
end
