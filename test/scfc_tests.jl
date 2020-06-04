function add_junk_file(scfc, size, path_prefix="")
    new_file = path_prefix * randstring(12)
    filepath = add!(scfc, new_file, UInt64(size))
    mkpath(dirname(filepath))
    open(filepath, "w") do io
        write(io, rand(UInt8, size))
    end
    return filepath
end

@testset "Basics" begin
    mktempdir() do scfc_root
        # Create an cache that keeps a constant size of 10KB,
        # and discards the least-recently-used entries first.
        scfc = SizeConstrainedFileCache(scfc_root, TargetSizeConstant(10*1024), DiscardLRU())

        filepath = add_junk_file(scfc, 1024)
        @test isfile(filepath)
        @test hit!(scfc, basename(filepath))
        @test filesize(filepath) == 1024
        @test scfc.total_size == 1024
        first_filepath = filepath

        filepath = add_junk_file(scfc, 512)
        @test isfile(filepath)
        @test filesize(filepath) == 512
        @test scfc.total_size == 1024 + 512

        # Delete that new one and see if it goes down:
        @test delete!(scfc, basename(filepath))
        @test !isfile(filepath)
        @test !hit!(scfc, basename(filepath))
        @test scfc.total_size == 1024

        # Test that deleting somethign twice doesn't do anything:
        @test !delete!(scfc, basename(filepath))
        @test scfc.total_size == 1024

        # Create a bunch more to fill up the cache:
        for idx in 1:9
            filepath = add_junk_file(scfc, 1024)
            @test isfile(filepath)
            @test scfc.total_size == 1024*(idx + 1)
        end

        # Add one more, and ensure that the first file gets removed
        add_junk_file(scfc, 16)
        @test scfc.total_size == 1024*9 + 16
        @test !isfile(first_filepath)

        # Add lots more small ones, ensuring they do not get removed until much later:
        for idx in 1:62
            filepath = add_junk_file(scfc, 16)
            @test isfile(filepath)
            @test scfc.total_size == 1024*9 + 16*(idx + 1)
        end
        add_junk_file(scfc, 16)
        @test scfc.total_size == 1024*10

        # Now, add a big, honking new object that is not perfectly sized;
        # this will clear most of the cache, but a few objects will remain
        filepath = add_junk_file(scfc, 9*1024 + 17)
        @test isfile(filepath)
        @test scfc.total_size == 9*1024 + 17 + 62*16

        # Ensure that the file sizes within the cache are one big guy and 62 small dudes
        @test count([v.size == 9*1024 + 17 for (k, v) in scfc.entries]) == 1
        @test count([v.size == 16 for (k, v) in scfc.entries]) == 62

        # Next, delete the big guy and rebuild the cache:
        rm(filepath; force=true)
        rebuild!(scfc)
        @test scfc.total_size == 62*16

        # Next, try adding files within folders:
        for idx in 1:3
            filepath = add_junk_file(scfc, 1024, "subdir/")
            @test scfc.total_size == idx*1024 + 62*16
        end

        # Now instead of just rebuilding, we'll create an entirely new scfc object and make sure
        # it correctly picks up all files
        scfc = SizeConstrainedFileCache(scfc_root, TargetSizeConstant(10*1024), DiscardLRU())
        @test scfc.total_size == 3*1024 + 62*16
        @test count([startswith(k, "subdir/") for (k, v) in scfc.entries]) == 3
        @test count([!startswith(k, "subdir/") for (k, v) in scfc.entries]) == 62

        # This time with a smaller target size, to ensure it runs a shrink immediately.
        # We can't tell exactly what would be deleted here, if the platform we're running on
        # doesn't track `mtime`'s properly; so we'll just assert that the total size satisfies
        # the constraint and call it good:
        scfc = SizeConstrainedFileCache(scfc_root, TargetSizeConstant(2*1024), DiscardLRU())
        @test scfc.total_size <= 2*1024

        # Also ensure that trying to cache something too big fails:
        @test_throws ArgumentError add_junk_file(scfc, 100*1024)

        # Test that add!()'ing something that already exists replaces it:
        k, e = first(scfc.entries)
        add!(scfc, k, UInt64(100))
        @test scfc.total_size == 1024 + 100
        @test length(scfc.entries) == 2
    end
end

@testset "LRU semantics" begin
    mktempdir() do scfc_root
        # Create an cache that keeps a constant size of 10KB,
        # and discards the least-recently-used entries first.
        scfc = SizeConstrainedFileCache(scfc_root, TargetSizeConstant(10*1024), DiscardLRU())

        # Add ten entries
        filepaths = String[]
        for idx in 1:10
            filepath = add_junk_file(scfc, 1024)
            push!(filepaths, filepath)
            @test isfile(filepaths[end])
            @test scfc.total_size == 1024*idx
        end

        # Add one more thing, ensure it was the first-created thing that gets removed:
        filepath = add_junk_file(scfc, 1024)
        push!(filepaths, filepath)
        @test isfile(filepaths[end])
        @test !isfile(popfirst!(filepaths))
        @test scfc.total_size == 10*1024

        # `hit!()` the oldest key now, and ensure that adding another file doesn't kill it,
        # but instead kills the second-to-oldest key:
        @test hit!(scfc, basename(filepaths[1]))
        filepath = add_junk_file(scfc, 1024)
        push!(filepaths, filepath)
        @test isfile(filepaths[end])
        @test isfile(filepaths[1])
        @test !isfile(filepaths[2])
        @test scfc.total_size == 10*1024

        # Ensure that `hit!()`'ing filepaths[2] fails
        @test hit!(scfc, basename(filepaths[2])) == false
    end
end

@testset "LFU semantics" begin
    mktempdir() do scfc_root
        # Create an cache that keeps a constant size of 10KB,
        # and discards the least-frequently-used entries first.
        scfc = SizeConstrainedFileCache(scfc_root, TargetSizeConstant(10*1024), DiscardLFU())

        # Add ten entries, and hit them such that the 2nd and 7th entries will get removed first:
        filepaths = String[]
        for idx in 1:10
            filepath = add_junk_file(scfc, 1024)
            push!(filepaths, filepath)
            @test isfile(filepaths[end])
            @test scfc.total_size == 1024*idx
            if idx != 2 && idx != 7
                @test hit!(scfc, basename(filepath))
            end
        end

        # Add two more files, ensure that the 2nd and 7th entries get removed first.
        # Note that here we rely upon the fallback behavior of the LFU discarding LRU
        # entries when the frequency is a tie; otherwise, we might add a single entry
        # and drop the 2nd element, then when we try to add another and drop the 7th
        # we would instead accidentally drop the entry we had just added.  The LFU
        # will instead always drop the 7th element, as it will be less-recently-used.
        add_junk_file(scfc, 1024)
        add_junk_file(scfc, 1024)
        @test !isfile(filepaths[2])
        @test !isfile(filepaths[7])
        @test scfc.total_size == 10*1024
    end
end

@testset "TargetSizeKeepFree" begin
    mktempdir() do scfc_root
        # Keep (current_freespace - 100MB) free, essentiall allowing this scfc to grow up to 100MB
        keep_free = get_disk_freespace(scfc_root) - 100*1024*1024
        scfc = SizeConstrainedFileCache(scfc_root, TargetSizeKeepFree(keep_free), DiscardLRU())

        # Add five entries, checking each time that the disk space is going down roughly as we expect.
        # Note that other activity on the machine can cause this to be a little flaky, we might have
        # to disable this test.
        filepaths = String[]
        starting_freespace = get_disk_freespace(scfc_root)
        for idx in 1:5
            filepath = add_junk_file(scfc, 10*1024*1024)
            push!(filepaths, filepath)
            @test isfile(filepaths[end])
            @test scfc.total_size == 10*1024*1024*idx
            @test abs(Int64(starting_freespace - (get_disk_freespace(scfc_root) + idx*10*1024*1024))) < 5*1024*1024
        end

        # If we now try to add an 80MB file, test that at least the first two chunks we added get removed:
        add_junk_file(scfc, 80*1024*1024)
        @test !isfile(filepaths[1])
        @test !isfile(filepaths[2])
    end
end