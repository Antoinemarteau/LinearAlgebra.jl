# This file is a part of Julia. License is MIT: https://julialang.org/license

module TestEigen

isdefined(Main, :pruned_old_LA) || @eval Main include("prune_old_LA.jl")

using Test, LinearAlgebra, Random
using LinearAlgebra: BlasComplex, BlasFloat, BlasReal, QRPivoted, UtiAUi!

n = 10

# Split n into 2 parts for tests needing two matrices
n1 = div(n, 2)
n2 = 2*n1

Random.seed!(12343219)

areal = randn(n,n)/2
aimg  = randn(n,n)/2

@testset for eltya in (Float32, Float64, ComplexF32, ComplexF64, Int)
    aa = eltya == Int ? rand(1:7, n, n) : convert(Matrix{eltya}, eltya <: Complex ? complex.(areal, aimg) : areal)
    asym = aa' + aa                  # symmetric indefinite
    apd  = aa' * aa                 # symmetric positive-definite
    for (a, asym, apd) in ((aa, asym, apd),
                           (view(aa, 1:n, 1:n),
                            view(asym, 1:n, 1:n),
                            view(apd, 1:n, 1:n)))
        ε = εa = eps(abs(float(one(eltya))))

        α = rand(eltya)
        β = rand(eltya)
        eab = eigen(α,β)
        @test eab.values == eigvals(fill(α,1,1),fill(β,1,1))
        @test eab.vectors == eigvecs(fill(α,1,1),fill(β,1,1))

        @testset "non-symmetric eigen decomposition" begin
            d, v = eigen(a)
            for i in 1:size(a,2)
                @test a*v[:,i] ≈ d[i]*v[:,i]
            end
            f = eigen(a)
            @test det(a) ≈ det(f)
            @test inv(a) ≈ inv(f)
            @test isposdef(a) == isposdef(f)
            @test eigvals(f) === f.values
            @test eigvecs(f) === f.vectors
            @test Array(f) ≈ a

            for T in (Tridiagonal(a), Hermitian(Tridiagonal(a), :U), Hermitian(Tridiagonal(a), :L))
                f = eigen(T)
                d, v = f
                for i in 1:size(a,2)
                    @test T*v[:,i] ≈ d[i]*v[:,i]
                end
                @test eigvals(T) ≈ d
                @test det(T) ≈ det(f)
                @test inv(T) ≈ inv(f)
            end

            num_fact = eigen(one(eltya))
            @test num_fact.values[1] == one(eltya)
            h = asym
            @test minimum(eigvals(h)) ≈ eigmin(h)
            @test maximum(eigvals(h)) ≈ eigmax(h)
            @test_throws DomainError eigmin(a - a')
            @test_throws DomainError eigmax(a - a')
        end
        @testset "symmetric generalized eigenproblem" begin
            if isa(a, Array)
                asym_sg = asym[1:n1, 1:n1]
                a_sg = a[:,n1+1:n2]
            else
                asym_sg = view(asym, 1:n1, 1:n1)
                a_sg = view(a, 1:n, n1+1:n2)
            end
            ASG2 = a_sg'a_sg
            f = eigen(asym_sg, ASG2)
            @test asym_sg*f.vectors ≈ (ASG2*f.vectors) * Diagonal(f.values)
            @test f.values ≈ eigvals(asym_sg, ASG2)
            @test prod(f.values) ≈ prod(eigvals(asym_sg/(ASG2))) atol=200ε
            @test eigvecs(asym_sg, ASG2) == f.vectors
            @test eigvals(f) === f.values
            @test eigvecs(f) === f.vectors
            @test_throws FieldError f.Z

            d,v = eigen(asym_sg, ASG2)
            @test d == f.values
            @test v == f.vectors

            # solver for in-place U' \ A / U (#14896)
            if !(eltya <: Integer)
                for atyp in (eltya <: Real ? (Symmetric, Hermitian) : (Hermitian,))
                    for utyp in (UpperTriangular, Diagonal), uplo in (:L, :U)
                        A = atyp(asym_sg, uplo)
                        U = utyp(ASG2)
                        @test UtiAUi!(copy(A), U) ≈ U' \ A / U
                    end
                end
            end

            # matrices of different types (#14896)
            D = Diagonal(ASG2)
            for uplo in (:L, :U)
                if eltya <: Real
                    fs = eigen(Symmetric(asym_sg, uplo), ASG2)
                    @test fs.values ≈ f.values
                    @test abs.(fs.vectors) ≈ abs.(f.vectors)  # may change sign
                    gs = eigen(Symmetric(asym_sg, uplo), D)
                    @test Symmetric(asym_sg, uplo)*gs.vectors ≈ (D*gs.vectors) * Diagonal(gs.values)
                end
                fh = eigen(Hermitian(asym_sg, uplo), ASG2)
                @test fh.values ≈ f.values
                @test abs.(fh.vectors) ≈ abs.(f.vectors)  # may change sign
                gh = eigen(Hermitian(asym_sg, uplo), D)
                @test Hermitian(asym_sg, uplo)*gh.vectors ≈ (D*gh.vectors) * Diagonal(gh.values)
                gd = eigen(Matrix(Hermitian(ASG2, uplo)), D)
                @test Hermitian(ASG2, uplo) * gd.vectors ≈ D * gd.vectors * Diagonal(gd.values)
                gd = eigen(Hermitian(Tridiagonal(ASG2), uplo), D)
                @test Hermitian(Tridiagonal(ASG2), uplo) * gd.vectors ≈ D * gd.vectors * Diagonal(gd.values)
            end
            gd = eigen(D, D)
            @test all(≈(1), gd.values)
            @test D * gd.vectors ≈ D * gd.vectors * Diagonal(gd.values)
            gd = eigen(Matrix(D), D)
            @test D * gd.vectors ≈ D * gd.vectors * Diagonal(gd.values)
            gd = eigen(D, Matrix(D))
            @test D * gd.vectors ≈ D * gd.vectors * Diagonal(gd.values)
            gd = eigen(Tridiagonal(ASG2), Matrix(D))
            @test Tridiagonal(ASG2) * gd.vectors ≈ D * gd.vectors * Diagonal(gd.values)
        end
        @testset "Non-symmetric generalized eigenproblem" begin
            if isa(a, Array)
                a1_nsg = a[1:n1, 1:n1]
                a2_nsg = a[n1+1:n2, n1+1:n2]
            else
                a1_nsg = view(a, 1:n1, 1:n1)
                a2_nsg = view(a, n1+1:n2, n1+1:n2)
            end
            sortfunc = x -> real(x) + imag(x)
            f = eigen(a1_nsg, a2_nsg; sortby = sortfunc)
            @test a1_nsg*f.vectors ≈ (a2_nsg*f.vectors) * Diagonal(f.values)
            @test f.values ≈ eigvals(a1_nsg, a2_nsg; sortby = sortfunc)
            @test prod(f.values) ≈ prod(eigvals(a1_nsg/a2_nsg, sortby = sortfunc)) atol=50000ε
            @test eigvecs(a1_nsg, a2_nsg; sortby = sortfunc) == f.vectors
            @test_throws FieldError f.Z

            g = eigen(a1_nsg, Diagonal(1:n1))
            @test a1_nsg*g.vectors ≈ (Diagonal(1:n1)*g.vectors) * Diagonal(g.values)

            d,v = eigen(a1_nsg, a2_nsg; sortby = sortfunc)
            @test d == f.values
            @test v == f.vectors
        end
    end
end

@testset "eigenvalue computations with NaNs" begin
    for eltya in (NaN16, NaN32, NaN)
        @test_throws(ArgumentError, eigen(fill(eltya, 1, 1)))
        @test_throws(ArgumentError, eigen(fill(eltya, 2, 2)))
        test_matrix = rand(typeof(eltya),3,3)
        test_matrix[1,3] = eltya
        @test_throws(ArgumentError, eigen(test_matrix))
        @test_throws(ArgumentError, eigvals(test_matrix))
        @test_throws(ArgumentError, eigvecs(test_matrix))
        @test_throws(ArgumentError, eigen(Symmetric(test_matrix)))
        @test_throws(ArgumentError, eigvals(Symmetric(test_matrix)))
        @test_throws(ArgumentError, eigvecs(Symmetric(test_matrix)))
        @test_throws(ArgumentError, eigen(Hermitian(test_matrix)))
        @test_throws(ArgumentError, eigvals(Hermitian(test_matrix)))
        @test_throws(ArgumentError, eigvecs(Hermitian(test_matrix)))
        @test_throws(ArgumentError, eigen(Hermitian(complex.(test_matrix))))
        @test_throws(ArgumentError, eigvals(Hermitian(complex.(test_matrix))))
        @test_throws(ArgumentError, eigvecs(Hermitian(complex.(test_matrix))))
        @test eigen(Symmetric(test_matrix, :L)) isa Eigen
        @test eigen(Hermitian(test_matrix, :L)) isa Eigen
    end
end

# test a matrix larger than 140-by-140 for #14174
let aa = rand(200, 200)
    for a in (aa, view(aa, 1:n, 1:n))
        f = eigen(a)
        @test a ≈ f.vectors * Diagonal(f.values) / f.vectors
    end
end

@testset "rational promotion: issue #24935" begin
    A = [1//2 0//1; 0//1 2//3]
    for λ in (eigvals(A), @inferred(eigvals(Symmetric(A))))
        @test λ isa Vector{Float64}
        @test λ ≈ [0.5, 2/3]
    end
end

@testset "text/plain (REPL) printing of Eigen and GeneralizedEigen" begin
    A, B = randn(5,5), randn(5,5)
    e    = eigen(A)
    ge   = eigen(A, B)
    valsstring = sprint((t, s) -> show(t, "text/plain", s), e.values)
    vecsstring = sprint((t, s) -> show(t, "text/plain", s), e.vectors)
    factstring = sprint((t, s) -> show(t, "text/plain", s), e)
    @test factstring == "$(summary(e))\nvalues:\n$valsstring\nvectors:\n$vecsstring"
end

@testset "eigen of an Adjoint" begin
    Random.seed!(4)
    A = randn(3,3)
    @test eigvals(A') == eigvals(copy(A'))
    @test eigen(A')   == eigen(copy(A'))
    @test eigmin(A') == eigmin(copy(A'))
    @test eigmax(A') == eigmax(copy(A'))
end

@testset "equality of eigen factorizations" begin
    A1 = Float32[1 0; 0 2]
    A2 = Float64[1 0; 0 2]
    EA1 = eigen(A1)
    EA2 = eigen(A2)
    @test EA1 == EA2
    @test hash(EA1) == hash(EA2)
    @test isequal(EA1, EA2)

    # trivial RHS to ensure that values match exactly
    B1 = Float32[1 0; 0 1]
    B2 = Float64[1 0; 0 1]
    EA1B1 = eigen(A1, B1)
    EA2B2 = eigen(A2, B2)
    @test EA1B1 == EA2B2
    @test hash(EA1B1) == hash(EA2B2)
    @test isequal(EA1B1, EA2B2)
end

@testset "Float16" begin
    A = Float16[4. 12. -16.; 12. 37. -43.; -16. -43. 98.]
    B = eigen(A)
    B32 = eigen(Float32.(A))
    C = Float16[3 -2; 4 -1]
    D = eigen(C)
    D32 = eigen(Float32.(C))
    F = eigen(complex(C))
    F32 = eigen(complex(Float32.(C)))
    @test B isa Eigen{Float16, Float16, Matrix{Float16}, Vector{Float16}}
    @test B.values isa Vector{Float16}
    @test B.vectors isa Matrix{Float16}
    @test B.values ≈ B32.values
    @test B.vectors ≈ B32.vectors
    @test D isa Eigen{ComplexF16, ComplexF16, Matrix{ComplexF16}, Vector{ComplexF16}}
    @test D.values isa Vector{ComplexF16}
    @test D.vectors isa Matrix{ComplexF16}
    @test D.values ≈ D32.values
    @test D.vectors ≈ D32.vectors
    @test F isa Eigen{ComplexF16, ComplexF16, Matrix{ComplexF16}, Vector{ComplexF16}}
    @test F.values isa Vector{ComplexF16}
    @test F.vectors isa Matrix{ComplexF16}
    @test F.values ≈ F32.values
    @test F.vectors ≈ F32.vectors

    for T in (Float16, ComplexF16)
        D = Diagonal(T[1,2,4])
        A = Array(D)
        B = eigen(A)
        @test B isa Eigen{Float16, Float16, Matrix{Float16}, Vector{Float16}}
        @test B.values isa Vector{Float16}
        @test B.vectors isa Matrix{Float16}
    end
    D = Diagonal(ComplexF16[im,2,4])
    A = Array(D)
    B = eigen(A)
    @test B isa Eigen{Float16, ComplexF16, Matrix{Float16}, Vector{ComplexF16}}
    @test B.values isa Vector{ComplexF16}
    @test B.vectors isa Matrix{Float16}
end

@testset "complex eigen inference (#52289)" begin
    A = ComplexF64[1.0 0.0; 0.0 8.0]
    TC = Eigen{ComplexF64, ComplexF64, Matrix{ComplexF64}, Vector{ComplexF64}}
    TR = Eigen{ComplexF64, Float64, Matrix{ComplexF64}, Vector{Float64}}
    λ, v = @inferred Union{TR,TC} eigen(A)
    @test λ == [1.0, 8.0]
end

end # module TestEigen
