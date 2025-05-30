# This file is a part of Julia. License is MIT: https://julialang.org/license

module TestLU

isdefined(Main, :pruned_old_LA) || @eval Main include("prune_old_LA.jl")

using Test, LinearAlgebra, Random
using LinearAlgebra: ldiv!, BlasReal, BlasInt, BlasFloat, rdiv!

n = 10

# Split n into 2 parts for tests needing two matrices
n1 = div(n, 2)
n2 = 2*n1

Random.seed!(1234324)

areal = randn(n,n)/2
aimg  = randn(n,n)/2
breal = randn(n,2)/2
bimg  = randn(n,2)/2
creal = randn(n)/2
cimg  = randn(n)/2
dureal = randn(n-1)/2
duimg  = randn(n-1)/2
dlreal = randn(n-1)/2
dlimg  = randn(n-1)/2
dreal = randn(n)/2
dimg  = randn(n)/2

@testset for eltya in (Float32, Float64, ComplexF32, ComplexF64, BigFloat, Int)
    a = eltya == Int ? rand(1:7, n, n) :
        convert(Matrix{eltya}, eltya <: Complex ? complex.(areal, aimg) : areal)
    d = if eltya == Int
        Tridiagonal(rand(1:7, n-1), rand(1:7, n), rand(1:7, n-1))
    elseif eltya <: Complex
        convert(Tridiagonal{eltya}, Tridiagonal(
            complex.(dlreal, dlimg), complex.(dreal, dimg), complex.(dureal, duimg)))
    else
        convert(Tridiagonal{eltya}, Tridiagonal(dlreal, dreal, dureal))
    end
    εa = eps(abs(float(one(eltya))))

    if eltya <: BlasFloat
        @testset "LU factorization for Number" begin
            num = rand(eltya)
            @test (lu(num)...,) == (hcat(one(eltya)), hcat(num), [1])
            @test convert(Array, lu(num)) ≈ eltya[num]
        end
        @testset "Balancing in eigenvector calculations" begin
            A = convert(Matrix{eltya}, [ 3.0     -2.0      -0.9     2*eps(real(one(eltya)));
                                       -2.0      4.0       1.0    -eps(real(one(eltya)));
                                       -eps(real(one(eltya)))/4  eps(real(one(eltya)))/2  -1.0     0;
                                       -0.5     -0.5       0.1     1.0])
            F = eigen(A, permute=false, scale=false)
            @test F.vectors*Diagonal(F.values)/F.vectors ≈ A
            F = eigen(A)
            # @test norm(F.vectors*Diagonal(F.values)/F.vectors - A) > 0.01
        end
    end
    κ  = cond(a,1)
    @testset "(Automatic) Square LU decomposition" begin
        lua   = factorize(a)
        @test_throws FieldError lua.Z
        l,u,p = lua.L, lua.U, lua.p
        ll,ul,pl = @inferred lu(a)
        @test ll * ul ≈ a[pl,:]
        @test l*u ≈ a[p,:]
        @test (l*u)[invperm(p),:] ≈ a
        @test a * inv(lua) ≈ Matrix(I, n, n)
        @test copy(lua) == lua
        @test lu!(copy(lua),a) == lua
        if eltya <: BlasFloat
            # test conversion of LU factorization's numerical type
            bft = eltya <: Real ? LinearAlgebra.LU{BigFloat} : LinearAlgebra.LU{Complex{BigFloat}}
            bflua = convert(bft, lua)
            @test bflua.L*bflua.U ≈ big.(a)[p,:] rtol=εa*norm(a)
            @test Factorization{eltya}(lua) === lua
            # test Factorization with different eltype
            if eltya <: BlasReal
                @test Array(Factorization{Float16}(lua)) ≈ Array(lu(convert(Matrix{Float16}, a)))
                @test eltype(Factorization{Float16}(lua)) == Float16
            end
        end
        # compact printing
        lstring = sprint(show,l)
        ustring = sprint(show,u)
    end
    κd    = cond(Array(d),1)
    @testset "Tridiagonal LU" begin
        lud = @inferred lu(d)
        @test LinearAlgebra.issuccess(lud)
        @test @inferred(lu(lud)) == lud
        @test_throws FieldError lud.Z
        @test lud.L*lud.U ≈ lud.P*Array(d)
        @test lud.L*lud.U ≈ Array(d)[lud.p,:]
        @test AbstractArray(lud) ≈ d
        @test Array(lud) ≈ d
        if eltya != Int
            dlu = convert.(eltya, [1, 1])
            dia = convert.(eltya, [-2, -2, -2])
            tri = Tridiagonal(dlu, dia, dlu)
            L = lu(tri)
            @test lu!(tri) == L
            @test UpperTriangular(tri) == L.U
        end
    end
    @testset for eltyb in (Float32, Float64, ComplexF32, ComplexF64, Int)
        b  = eltyb == Int ? rand(1:5, n, 2) :
            convert(Matrix{eltyb}, eltyb <: Complex ? complex.(breal, bimg) : breal)
        c  = eltyb == Int ? rand(1:5, n) :
            convert(Vector{eltyb}, eltyb <: Complex ? complex.(creal, cimg) : creal)
        εb = eps(abs(float(one(eltyb))))
        ε  = max(εa,εb)
        @testset "(Automatic) Square LU decomposition" begin
            lua   = factorize(a)
            let Bs = copy(b), Cs = copy(c)
                for (bb, cc) in ((Bs, Cs), (view(Bs, 1:n, 1), view(Cs, 1:n)))
                    @test norm(a*(lua\bb) - bb, 1) < ε*κ*n*2 # Two because the right hand side has two columns
                    @test norm(a'*(lua'\bb) - bb, 1) < ε*κ*n*2 # Two because the right hand side has two columns
                    @test norm(a'*(lua'\a') - a', 1) < ε*κ*n^2
                    @test norm(a*(lua\cc) - cc, 1) < ε*κ*n # cc is a vector
                    @test norm(a'*(lua'\cc) - cc, 1) < ε*κ*n # cc is a vector
                    @test AbstractArray(lua) ≈ a
                    @test norm(transpose(a)*(transpose(lua)\bb) - bb,1) < ε*κ*n*2 # Two because the right hand side has two columns
                    @test norm(transpose(a)*(transpose(lua)\cc) - cc,1) < ε*κ*n
                end

                # Test whether Ax_ldiv_B!(y, LU, x) indeed overwrites y
                resultT = typeof(oneunit(eltyb) / oneunit(eltya))

                b_dest = similar(b, resultT)
                c_dest = similar(c, resultT)

                ldiv!(b_dest, lua, b)
                ldiv!(c_dest, lua, c)
                @test norm(b_dest - lua \ b, 1) < ε*κ*2n
                @test norm(c_dest - lua \ c, 1) < ε*κ*n

                ldiv!(b_dest, transpose(lua), b)
                ldiv!(c_dest, transpose(lua), c)
                @test norm(b_dest - transpose(lua) \ b, 1) < ε*κ*2n
                @test norm(c_dest - transpose(lua) \ c, 1) < ε*κ*n

                ldiv!(b_dest, adjoint(lua), b)
                ldiv!(c_dest, adjoint(lua), c)
                @test norm(b_dest - lua' \ b, 1) < ε*κ*2n
                @test norm(c_dest - lua' \ c, 1) < ε*κ*n

                if eltyb != Int && !(eltya <: Complex) || eltya <: Complex && eltyb <: Complex
                    p = Matrix(b')
                    q = Matrix(c')
                    p_dest = copy(p)
                    q_dest = copy(q)
                    rdiv!(p_dest, lua)
                    rdiv!(q_dest, lua)
                    @test norm(p_dest - p / lua, 1) < ε*κ*2n
                    @test norm(q_dest - q / lua, 1) < ε*κ*n
                end
            end
            if eltya <: BlasFloat && eltyb <: BlasFloat
                e = rand(eltyb,n,n)
                @test norm(e/lua - e/a,1) < ε*κ*n^2
            end
        end
        @testset "Tridiagonal LU" begin
            lud   = factorize(d)
            f = zeros(eltyb, n+1)
            @test_throws DimensionMismatch lud\f
            @test_throws DimensionMismatch transpose(lud)\f
            @test_throws DimensionMismatch lud'\f
            @test_throws DimensionMismatch LinearAlgebra.ldiv!(transpose(lud), f)
            let Bs = copy(b)
                for bb in (Bs, view(Bs, 1:n, 1))
                    @test norm(d*(lud\bb) - bb, 1) < ε*κd*n*2 # Two because the right hand side has two columns
                    if eltya <: Real
                        @test norm((transpose(lud)\bb) - Array(transpose(d))\bb, 1) < ε*κd*n*2 # Two because the right hand side has two columns
                        if eltya != Int && eltyb != Int
                            @test norm(LinearAlgebra.ldiv!(transpose(lud), copy(bb)) - Array(transpose(d))\bb, 1) < ε*κd*n*2
                        end
                    end
                    if eltya <: Complex
                        dummy_factor = 2.5
                        # TODO: Remove dummy_factor, this test started failing when the RNG stream changed
                        # so the factor was added.
                        @test norm((lud'\bb) - Array(d')\bb, 1) < ε*κd*n*2*dummy_factor # Two because the right hand side has two columns
                    end
                end
            end
            if eltya <: BlasFloat && eltyb <: BlasFloat
                e = rand(eltyb,n,n)
                @test norm(e/lud - e/d,1) < ε*κ*n^2
                @test norm((transpose(lud)\e') - Array(transpose(d))\e',1) < ε*κd*n^2
                #test singular
                du = rand(eltya,n-1)
                dl = rand(eltya,n-1)
                dd = rand(eltya,n)
                dd[1] = zero(eltya)
                du[1] = zero(eltya)
                dl[1] = zero(eltya)
                zT = Tridiagonal(dl,dd,du)
                @test !LinearAlgebra.issuccess(lu(zT; check = false))
            end
        end
        @testset "Thin LU" begin
            lua   = @inferred lu(a[:,1:n1])
            @test lua.L*lua.U ≈ lua.P*a[:,1:n1]
        end
        @testset "Fat LU" begin
            lua   = @inferred lu(a[1:n1,:])
            @test lua.L*lua.U ≈ lua.P*a[1:n1,:]
        end
    end

    @testset "LU of Symmetric/Hermitian" begin
        for HS in (Hermitian(a'a), Symmetric(a'a))
            luhs = @inferred lu(HS)
            @test luhs.L*luhs.U ≈ luhs.P*Matrix(HS)
        end
    end

    @testset "Factorization of symtridiagonal dense matrix with zero ldlt-pivot (#38026)" begin
        A = [0.0 -1.0 0.0 0.0
            -1.0 0.0 0.0 0.0
            0.0 0.0 0.0 -1.0
            0.0 0.0 -1.0 0.0]
        F = factorize(A)
        @test all((!isnan).(Matrix(F)))
    end
end

@testset "Small tridiagonal matrices" for T in (Float64, ComplexF64)
    A = Tridiagonal(T[], T[1], T[])
    @test inv(A) == A
end

@testset "Singular matrices" for T in (Float64, ComplexF64)
    A = T[1 2; 0 0]
    @test_throws SingularException lu(A)
    @test_throws SingularException lu!(copy(A))
    @test_throws SingularException lu(A; check = true)
    @test_throws SingularException lu!(copy(A); check = true)
    @test !issuccess(lu(A; check = false))
    @test !issuccess(lu!(copy(A); check = false))
    @test_throws ZeroPivotException lu(A, NoPivot())
    @test_throws ZeroPivotException lu!(copy(A), NoPivot())
    @test_throws ZeroPivotException lu(A, NoPivot(); check = true)
    @test_throws ZeroPivotException lu!(copy(A), NoPivot(); check = true)
    @test !issuccess(lu(A, NoPivot(); check = false))
    @test !issuccess(lu!(copy(A), NoPivot(); check = false))
    F = lu(A, NoPivot(); check = false)
    @test sprint((io, x) -> show(io, "text/plain", x), F) ==
        "Failed factorization of type $(typeof(F))"
    F2 = lu(A; allowsingular = true)
    @test !issuccess(F2)
    @test issuccess(F2, allowsingular = true)
    @test occursin("U factor (rank-deficient)", sprint((io, x) -> show(io, "text/plain", x), F2))
end

@testset "conversion" begin
    Random.seed!(4)
    a = Tridiagonal(rand(9),rand(10),rand(9))
    fa = Array(a)
    falu = lu(fa)
    alu = lu(a)
    falu = convert(typeof(falu),alu)
    @test Array(alu) == fa
    @test AbstractArray(alu) == fa
end

@testset "Rational Matrices" begin
    ## Integrate in general tests when more linear algebra is implemented in julia
    a = convert(Matrix{Rational{BigInt}}, rand(1:10//1,n,n))/n
    b = rand(1:10,n,2)
    @inferred lu(a)
    lua   = factorize(a)
    l,u,p = lua.L, lua.U, lua.p
    @test l*u ≈ a[p,:]
    @test l[invperm(p),:]*u ≈ a
    @test a*inv(lua) ≈ Matrix(I, n, n)
    let Bs = b
        for b in (Bs, view(Bs, 1:n, 1))
            @test a*(lua\b) ≈ b
        end
    end
    @test @inferred(det(a)) ≈ det(Array{Float64}(a))
end

@testset "Rational{BigInt} and BigFloat Hilbert Matrix" begin
    ## Hilbert Matrix (very ill conditioned)
    ## Testing Rational{BigInt} and BigFloat version
    nHilbert = 50
    H = Rational{BigInt}[1//(i+j-1) for i = 1:nHilbert,j = 1:nHilbert]
    Hinv = Rational{BigInt}[(-1)^(i+j)*(i+j-1)*binomial(nHilbert+i-1,nHilbert-j)*
        binomial(nHilbert+j-1,nHilbert-i)*binomial(i+j-2,i-1)^2
        for i = big(1):nHilbert,j=big(1):nHilbert]
    @test inv(H) == Hinv
    setprecision(2^10) do
        @test norm(Array{Float64}(inv(float(H)) - float(Hinv))) < 1e-100
    end
end

@testset "logdet" begin
    @test @inferred(logdet(ComplexF32[1.0f0 0.5f0; 0.5f0 -1.0f0])) === 0.22314355f0 + 3.1415927f0im
    @test_throws DomainError logdet([1 1; 1 -1])
end

@testset "REPL printing" begin
        bf = IOBuffer()
        show(bf, "text/plain", lu(Matrix(I, 4, 4)))
        seekstart(bf)
        @test String(take!(bf)) == """
$(LinearAlgebra.LU){Float64, Matrix{Float64}, Vector{$Int}}
L factor:
4×4 Matrix{Float64}:
 1.0  0.0  0.0  0.0
 0.0  1.0  0.0  0.0
 0.0  0.0  1.0  0.0
 0.0  0.0  0.0  1.0
U factor:
4×4 Matrix{Float64}:
 1.0  0.0  0.0  0.0
 0.0  1.0  0.0  0.0
 0.0  0.0  1.0  0.0
 0.0  0.0  0.0  1.0"""
end

@testset "propertynames" begin
    names = sort!(collect(string.(Base.propertynames(lu(rand(3,3))))))
    @test names == ["L", "P", "U", "p"]
    allnames = sort!(collect(string.(Base.propertynames(lu(rand(3,3)), true))))
    @test allnames == ["L", "P", "U", "factors", "info", "ipiv", "p"]
end

include("trickyarithmetic.jl")

@testset "lu with type whose sum is another type" begin
    A = TrickyArithmetic.A[1 2; 3 4]
    ElT = TrickyArithmetic.D{TrickyArithmetic.C,TrickyArithmetic.C}
    B = lu(A, NoPivot())
    @test B isa LinearAlgebra.LU{ElT,Matrix{ElT}}
end

@testset "Issue #30917. Determinant of integer matrix" begin
    @test det([1 1 0 0 1 0 0 0
               1 0 1 0 0 1 0 0
               1 0 0 1 0 0 1 0
               0 1 1 1 0 0 0 0
               0 1 0 0 0 0 1 1
               0 0 1 0 1 0 0 1
               0 0 0 1 1 1 0 0
               0 0 0 0 1 1 0 1]) ≈ 6
end

@testset "Issue #33177. No ldiv!(LU, Adjoint)" begin
    A = [1 0; 1 1]
    B = [1 2; 2 8]
    F = lu(B)
    @test (A  / F') * B == A
    @test (A' / F') * B == A'

    a = complex.(randn(2), randn(2))
    @test (a' / F') * B ≈ a'
    @test (transpose(a) / F') * B ≈ transpose(a)

    A = complex.(randn(2, 2), randn(2, 2))
    @test (A' / F') * B ≈ A'
    @test (transpose(A) / F') * B ≈ transpose(A)
end

@testset "0x0 matrix" begin
    A = ones(0, 0)
    F = lu(A)
    @test F.U == ones(0, 0)
    @test F.L == ones(0, 0)
    @test F.P == ones(0, 0)
    @test F.p == []
end

@testset "more rdiv! methods" begin
    for elty in (Float16, Float64, ComplexF64), transform in (transpose, adjoint)
        A = randn(elty, 5, 5)
        C = copy(A)
        B = randn(elty, 5, 5)
        @test rdiv!(transform(A), transform(lu(B))) ≈ transform(C) / transform(B)
    end
    for elty in (Float32, Float64, ComplexF64), transF in (identity, transpose),
            transB in (transpose, adjoint), transT in (identity, complex)
        A = randn(elty, 5, 5)
        F = lu(A)
        b = randn(transT(elty), 5)
        @test rdiv!(transB(copy(b)), transF(F)) ≈ transB(b) / transF(F) ≈ transB(b) / transF(A)
        B = randn(transT(elty), 5, 5)
        @test rdiv!(copy(B), transF(F)) ≈ B / transF(F) ≈ B / transF(A)
    end
end

@testset "transpose(A) / lu(B)' should not overwrite A (#36657)" begin
    for elty in (Float16, Float64, ComplexF64)
        A = randn(elty, 5, 5)
        B = randn(elty, 5, 5)
        C = copy(A)
        a = randn(elty, 5)
        c = copy(a)
        @test transpose(A) / lu(B)' ≈ transpose(A) / B'
        @test transpose(a) / lu(B)' ≈ transpose(a) / B'
        @test A == C
        @test a == c
    end
end

@testset "lu on *diagonal matrices" begin
    dl = rand(3)
    d = rand(4)
    Bl = Bidiagonal(d, dl, :L)
    Bu = Bidiagonal(d, dl, :U)
    Tri = Tridiagonal(dl, d, dl)
    Sym = SymTridiagonal(d, dl)
    D = Diagonal(d)
    b = ones(4)
    B = rand(4,4)
    for A in (Bl, Bu, Tri, Sym, D), pivot in (NoPivot(), RowMaximum())
        @test A\b ≈ lu(A, pivot)\b
        @test B/A ≈ B/lu(A, pivot)
        @test B/A ≈ B/Matrix(A)
        @test Matrix(lu(A, pivot)) ≈ A
        @test @inferred(lu(A)) isa LU
        if A isa Union{Bidiagonal, Diagonal, Tridiagonal, SymTridiagonal}
            @test lu(A) isa LU{Float64, Tridiagonal{Float64, Vector{Float64}}}
            @test lu(A, pivot) isa LU{Float64, Tridiagonal{Float64, Vector{Float64}}}
            @test lu(A, pivot; check = false) isa LU{Float64, Tridiagonal{Float64, Vector{Float64}}}
        end
    end
end

@testset "can push to vector after 3-arg ldiv! (#43507)" begin
    u = rand(3)
    A = rand(3,3)
    b = rand(3)
    ldiv!(u,lu(A),b)
    push!(b,4.0)
    @test length(b) == 4
end

@testset "NaN matrix should throw error" begin
    for eltya in (NaN16, NaN32, NaN64, BigFloat(NaN))
        r = fill(eltya, 2, 3)
        c = fill(complex(eltya, eltya), 2, 3)
        @test_throws ArgumentError lu(r)
        @test_throws ArgumentError lu(c)
    end
end

@testset "more generic ldiv! #35419" begin
    A = rand(3, 3)
    b = rand(3)
    @test A * ldiv!(lu(A), Base.ReshapedArray(copy(b)', (3,), ())) ≈ b
end

@testset "generic lu!" begin
    A = rand(3,3); B = deepcopy(A); C = A[2:3,2:3]
    Asub1 = @view(A[2:3,2:3])
    F1 = lu!(Asub1)
    Asub2 = @view(B[[2,3],[2,3]])
    F2 = lu!(Asub2)
    @test Matrix(F1) ≈ Matrix(F2) ≈ C
end

@testset "matrix with Nonfinite" begin
    lu(fill(NaN, 2, 2), check=false)
    lu(fill(Inf, 2, 2), check=false)
    LinearAlgebra.generic_lufact!(fill(NaN, 2, 2), check=false)
    LinearAlgebra.generic_lufact!(fill(Inf, 2, 2), check=false)
end

@testset "lu for empty matrices" begin
    for T in (Float64, BigFloat)
        A = fill(T(0.0), 0, 0)
        v = fill(T(1.0), 0, 10)
        @test A \ v ≈ lu(A) \ v
        vt = permutedims(v)
        @test vt / A ≈ vt / lu(A)
        B = UpperTriangular(transpose(fill(complex(T(0.0)), 0, 0)'))
        @test B \ v ≈ v
        @test vt / B ≈ vt
    end
end

end # module TestLU
