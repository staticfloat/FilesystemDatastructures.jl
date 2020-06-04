using SnoopCompile, Random
ENV["FILESYSTEMDATASTRUCTURES_GENERATING_PRECOMPILE"] = "true"

inf_timing = @snoopi tmin=0.001 begin
    using FilesystemDatastructures

    mktempdir() do root
        for target_size in (TargetSizeKeepFree(10*1024), TargetSizeConstant(10*1024)),
            discard_policy in (DiscardLRU(), DiscardLFU())

            scfc = SizeConstrainedFileCache(root, target_size, discard_policy)

            for idx in 1:100
                key = randstring(12)
                filesize = rand(512:1024)
                filedata = rand(UInt8, filesize)
                path = add!(scfc, key, filesize)
                open(path, "w") do io
                    write(path, filedata)
                end

                for k in keys(scfc.entries)
                    if rand() > 0.8
                        hit!(scfc, k)
                    end
                    if rand() > 0.98
                        delete!(scfc, k)
                    end
                end
            end
        end
    end
end

pc = SnoopCompile.parcel(inf_timing)
mktempdir() do dir
    SnoopCompile.write(dir, pc)
    cp(joinpath(dir, "precompile_FilesystemDatastructures.jl"),
       joinpath(@__DIR__, "precompile.jl"); force=true)
end