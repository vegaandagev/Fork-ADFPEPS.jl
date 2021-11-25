using ADFPEPS
using ADFPEPS: parity_conserving
using CUDA
using LinearAlgebra
using Random
using Test
using VUMPS:num_grad
using ADFPEPS:HamiltonianModel
using Zygote
CUDA.allowscalar(false)

@testset "parity_conserving" for atype in [Array], dtype in [ComplexF64], Ni = [2], Nj = [2]
    Random.seed!(100)
    Nv = 2
    T = atype(rand(dtype,D,D,4,D,D,4))
    function foo(T)
        ipeps = reshape([parity_conserving(T[:,:,:,:,:,i]) for i = 1:4], (2, 2))
        norm(ipeps)
    end
    @test Zygote.gradient(foo, T)[1] ≈ num_grad(foo, T) atol = 1e-8
end