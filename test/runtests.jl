using FilesystemDatastructures, Test, Random

@testset "SizeConstrainedFileCache" begin
    include("scfc_tests.jl")
end

@testset "DiskUtils" begin
    include("diskutils_tests.jl")
end