function add_file(fc, key)
    filepath = add!(fc, key)
    touch(filepath)
    sleep(0.1)
    return filepath
end
mktempdir() do fc_root
    # Cache with max 5 files and LRU
    fc = NFileCache(fc_root, 5, DiscardLRU())

    # Add 5 some files
    for i in 1:5
        key = "file-$i"
        file = add_file(fc, key)
        @test hit!(fc, key)
        @test file == filepath(fc, key)
        @test isfile(file)
        @test length(fc.entries) == i
    end
    @test length(fc.entries) == 5
    @test fc.discard_ordering(fc) == ["file-$i" for i in 1:5]

    # Add a 6th file, should delete file-1
    file = add_file(fc, "file-6")
    @test length(fc.entries) == 5
    @test !(hit!(fc, "file-1"))


    # Cache with max 5 files and LFU
    foreach(f -> rm(f), readdir(fc_root; join=true))
    fc = NFileCache(fc_root, 5, DiscardLFU())
    for i in 1:5
        add_file(fc, "file-$i")
        foreach((x) -> hit!(fc, "file-$i"), 1:(5-i))
    end
    @test fc.discard_ordering(fc) == ["file-$i" for i in 5:-1:1]

    # Add a 6th file, should delete file-5
    file = add_file(fc, "file-6")
    @test length(fc.entries) == 5
    @test !(hit!(fc, "file-5"))

    # Optional byte counter
    foreach(f -> rm(f), readdir(fc_root; join=true))
    fc = NFileCache(fc_root, 5, DiscardLRU())
    @test fc.total_size == 0
    add!(fc, "hello", 10)
    @test fc.total_size == 10
    delete!(fc, "hello")
    @test fc.total_size == 0

    # Cache creation with existing files
    foreach(f -> rm(f), readdir(fc_root; join=true))
    foreach(i -> (touch(joinpath(fc_root, "file-$i")); sleep(0.1)), 1:6)
    fc = NFileCache(fc_root, 5, DiscardLRU())
    # file-1 should be deleted based on mtime
    @test !(hit!(fc, "file-1"))
    @test length(fc.entries) == 5
end
