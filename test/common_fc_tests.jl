using FilesystemDatastructures, Test

@testset "predicate function" begin
    mktempdir() do fc_root
        for f in joinpath.(fc_root, ("include", "no-include"))
            open(io -> write(f, "hello"), f, "w")
        end
        predicate = x -> begin
            # test that we get a key and not e.g. the full path
            @test x ∈ ("include", "no-include")
            return x == "include"
        end
        fc = SizeConstrainedFileCache(fc_root, TargetSizeConstant(1024), DiscardLRU();
                                      predicate=predicate)
        @test hit!(fc, "include")
        @test !hit!(fc, "no-include")

        fc = NFileCache(fc_root, 10, DiscardLRU(); predicate=predicate)
        @test hit!(fc, "include")
        @test !hit!(fc, "no-include")
    end
end
