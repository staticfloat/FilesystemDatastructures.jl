function make_file(path::AbstractString, size)
    open(path, "w") do io
        written = 0
        while written < size
            batch = min(2*1024*1024, size - written)
            written += write(io, zeros(UInt8, batch))
        end
    end
end

@testset "get_disk_freespace" begin
    mktempdir() do dir
        # Note that other disk activity can cause this test to be a little noisy,
        # so we do approximate math and use large file sizes in an attempt to be
        # more robust against random fluctuations.
        freespace = get_disk_freespace(dir)
        make_file(joinpath(dir, "big"), 50*1024*1024)
        @test abs(Int64(freespace - get_disk_freespace(dir)) - 50*1024*1024) < 20*1024*1024
        rm(joinpath(dir, "big"); force=true)
        @test abs(Int64(freespace - get_disk_freespace(dir))) < 20*1024*1024
    end
end