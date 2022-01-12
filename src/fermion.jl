# contains some utils for Fermionic Tensor Network Construction

using BitBasis
using CUDA
using VUMPS
using VUMPS: dtr
using Zygote

include("contractrules.jl")

_arraytype(::Array{T}) where {T} = Array
_arraytype(::CuArray{T}) where {T} = CuArray

"""
    parity_conserving(T::Array)

Transform an arbitray tensor which has arbitray legs and each leg have index 1 or 2 into parity conserving form

# example

```julia
julia> T = rand(2,2,2)
2×2×2 Array{Float64, 3}:
[:, :, 1] =
 0.863822  0.133604
 0.865495  0.371586

[:, :, 2] =
 0.581621  0.819325
 0.197463  0.801167

julia> parity_conserving(T)
2×2×2 Array{Float64, 3}:
[:, :, 1] =
 0.863822  0.0
 0.0       0.371586

[:, :, 2] =
 0.0       0.819325
 0.197463  0.0
```
"""
function parity_conserving(T::Union{Array,CuArray}) where V<:Real
	s = size(T)
	p = zeros(s)
	bits = map(x -> Int(ceil(log2(x))), s)
	for index in CartesianIndices(T)
		i = Tuple(index) .- 1
		sum(sum.(bitarray.(i,bits))) % 2 == 0 && (p[index] = 1)
	end
	p = _arraytype(T)(p)

	return reshape(p.*T,s...)
end

"""
    function swapgate(n1::Int,n2::Int)

Generate a tensor which represent swapgate in Fermionic Tensor Network. n1,n2 should be power of 2.
The generated tensor have 4 indices. (ijkl).
S(ijkl) = delta(ik)*delta(jl)*parity(gate)

# example
```
julia> swapgate(2,4)
2×4×2×4 Array{Int64, 4}:
[:, :, 1, 1] =
 1  0  0  0
 0  0  0  0

[:, :, 2, 1] =
 0  0  0  0
 1  0  0  0

[:, :, 1, 2] =
 0  1  0  0
 0  0  0  0

[:, :, 2, 2] =
 0   0  0  0
 0  -1  0  0

[:, :, 1, 3] =
 0  0  1  0
 0  0  0  0

[:, :, 2, 3] =
 0  0   0  0
 0  0  -1  0

[:, :, 1, 4] =
 0  0  0  1
 0  0  0  0

[:, :, 2, 4] =
 0  0  0  0
 0  0  0  1
```
"""
function swapgate(n1::Int,n2::Int)
	S = ein"ij,kl->ikjl"(Matrix{ComplexF64}(I,n1,n1),Matrix{ComplexF64}(I,n2,n2))
	for j = 1:n2, i = 1:n1
		sum(bitarray(i-1,Int(ceil(log2(n1)))))%2 != 0 && sum(bitarray(j-1,Int(ceil(log2(n2)))))%2 != 0 && (S[i,j,:,:] .= -S[i,j,:,:])
	end
	return S
end

"""
    function fdag(T::Array{V,5}) where V<:Number

Obtain dag tensor for local peps tensor in Fermionic Tensor Network(by inserting swapgates). The input tensor has indices which labeled by (lurdf)
legs are counting from f and clockwisely.

input legs order: ulfdr
output legs order: ulfdr
"""
function fdag(T::Union{Array{V,5},CuArray{V,5}}, SDD::Union{Array{V,4},CuArray{V,4}}) where V<:Number
	ein"(ulfdr,luij),rdpq->jifqp"(conj(T), SDD, SDD)
end

function fdag(T::AbstractZ2Array, SDD::AbstractZ2Array)
	ein"(ulfdr,luij),rdpq->jifqp"(conj(T), SDD, SDD)
end

"""
    function bulk(T::Array{V,5}) where V<: Number
    
Obtain bulk tensor in peps, while the input tensor has indices which labeled by (lurdf).
This tensor is ready for GCTMRG (general CTMRG) algorithm
"""
function bulk(T::Union{Array{V,5},CuArray{V,5}}, SDD::Union{Array{V,4},CuArray{V,4}}) where V<:Number
	nu,nl,nf,nd,nr = size(T)
	Tdag = fdag(T, SDD)
	return	_arraytype(T)(reshape(ein"((abcde,fgchi),bflm),dijk -> glhjkema"(T,Tdag,SDD,SDD),nu^2,nl^2,nd^2,nr^2))
end

function bulk(T::AbstractZ2Array, SDD::AbstractZ2Array)
	nu,nl,nf,nd,nr = size(T)
	Tdag = fdag(T, SDD)
	return Z2reshape(ein"((abcde,fgchi),bflm),dijk -> glhjkema"(T,Tdag,SDD,SDD),nu^2,nl^2,nd^2,nr^2)
end

"""
    function bulkop(T::Array{V,5}) where V<: Number
    
Obtain bulk tensor in peps, while the input tensor has indices which labeled by (lurdf).
This tensor is ready for GCTMRG (general CTMRG) algorithm
"""
function bulkop(T::Union{Array{V,5},CuArray{V,5}}, SDD::Union{Array{V,4},CuArray{V,4}}) where V<:Number
	nu,nl,nf,nd,nr = size(T)
	Tdag = fdag(T, SDD)
	return	_arraytype(T)(reshape(ein"((abcde,fgnhi),bflm),dijk -> glhjkencma"(T,Tdag,SDD,SDD),nu^2,nl^2,nd^2,nr^2,nf,nf))
end

"""
	calculate enviroment (E1...E6)
	a ────┬──── c 
	│     b     │ 
	├─ d ─┼─ e ─┤ 
	│     g     │ 
	f ────┴──── h 
	order: adf,abc,dgeb,fgh,ceh
"""
function ipeps_enviroment(M::AbstractArray, key)
	folder, model, Ni, Nj, symmetry, atype, D, χ, tol, maxiter = key

	# VUMPS
	_, ALu, Cu, ARu, ALd, Cd, ARd, FLo, FRo, FL, FR = obs_env(M; χ=χ, maxiter=maxiter, miniter=1, tol = tol, verbose=true, savefile= true, infolder=folder*"/$(model)_$(Ni)x$(Nj)/", outfolder=folder*"/$(model)_$(Ni)x$(Nj)/", updown = true, downfromup = false, show_every=Inf)

	E1 = FLo
	E2 = reshape([ein"abc,cd->abd"(ALu[i],Cu[i]) for i = 1:Ni*Nj], (Ni, Nj))
	E3 = ARu
	E4 = FRo
	E5 = ARd
	E6 = reshape([ein"abc,cd->abd"(ALd[i],Cd[i]) for i = 1:Ni*Nj], (Ni, Nj))
	E7 = FL
	E8 = FR

	return (E1,E2,E3,E4,E5,E6,E7,E8)
end

ABBA(i) = i in [1,4] ? 1 : 2

function double_ipeps_energy(ipeps::AbstractArray, key)	
	folder, model, Ni, Nj, symmetry, atype, D, χ, tol, maxiter = key
	T = reshape([parity_conserving(ipeps[:,:,:,:,:,ABBA(i)]) for i = 1:Ni*Nj], (Ni, Nj))
	SdD = Zygote.@ignore atype(swapgate(4, D))
	SDD = Zygote.@ignore atype(swapgate(D, D))
	# M = reshape([bulk(T[i], SDD) for i = 1:Ni*Nj], (Ni, Nj))
	if symmetry == :Z2 
		SdD, SDD = map(tensor2Z2tensor, [SdD, SDD])
		T = map(tensor2Z2tensor, T)
		# M = map(tensor2Z2tensor, M)
	end
	M = reshape([bulk(T[i], SDD) for i = 1:Ni*Nj], (Ni, Nj))

	E1,E2,E3,E4,E5,E6,E7,E8 = ipeps_enviroment(M, key)
	
	hx = reshape(atype{ComplexF64}(hamiltonian(model)), 4, 4, 4, 4)
	hy = reshape(atype{ComplexF64}(hamiltonian(model)), 4, 4, 4, 4)
	if symmetry == :Z2
		hx = Zygote.@ignore tensor2Z2tensor(hx)
		hy = Zygote.@ignore tensor2Z2tensor(hy)
	end

	etol = 0
	for j = 1:Nj, i = 1:Ni
		ir = Ni + 1 - i
		jr = j + 1 - (j==Nj) * Nj
		
		Tij, Tijr, Tirj = T[i,j], T[i,jr], T[ir,j]
		ex = (E1[i,j],E2[i,j],E3[i,jr],E4[i,jr],E5[ir,jr],E6[ir,j])
		ρx = square_ipeps_contraction_horizontal(Tij, Tijr, SdD, SDD, ex, symmetry)
		# ρ1 = reshape(ρ,16,16)
		# @show norm(ρ1-ρ1')
        Ex = ein"ijkl,ijkl -> "(ρx,hx)[]
		nx = dtr(ρx) # nx = ein"ijij -> "(ρx)
		etol += Ex/nx
		println("─ = $(Ex/nx)") 

        ey = (E1[ir,j],E2[i,j],E4[ir,j],E6[i,j],E7[i,j],E8[i,j])
		ρy = square_ipeps_contraction_vertical(Tij, Tirj, SdD, SDD, ey, symmetry)
		# ρ1 = reshape(ρ,16,16)
		# @show norm(ρ1-ρ1')
        Ey = ein"ijkl,ijkl -> "(ρy,hy)[]
		ny = dtr(ρy) # ny = ein"ijij -> "(ρy)[]
		etol += Ey/ny
		println("│ = $(Ey/ny)")
	end

	return real(etol)/Ni/Nj
end

function square_ipeps_contraction_vertical(T1, T2, SdD, SDD, env, symmetry)
	nu,nl,nf,nd,nr = size(T1)
	χ = size(env[1])[1]
	if symmetry == :Z2
		(E1,E2,E4,E6,E7,E8) = map(x->Z2reshape(x,(χ,nl,nl,χ)),env)
	else
		(E1,E2,E4,E6,E7,E8) = map(x->reshape(x,(χ,nl,nl,χ)),env)
	end
	result = VERTICAL_RULES(T1,fdag(T1, SDD),SDD,SdD,SdD,SDD,T2,fdag(T2, SDD),SDD,SdD,SdD,SDD,
	E2,E8,E4,E6,E1,E7)
	return result
end

function square_ipeps_contraction_horizontal(T1, T2, SdD, SDD, env, symmetry)
	nu,nl,nf,nd,nr = size(T1)
	χ = size(env[1])[1]
	if symmetry == :Z2
		(E1,E2,E3,E4,E5,E6) = map(x->Z2reshape(x,(χ,nl,nl,χ)),env)
	else
		(E1,E2,E3,E4,E5,E6) = map(x->reshape(x,(χ,nl,nl,χ)),env)
	end
	result = HORIZONTAL_RULES(T1,SdD,fdag(T1, SDD),SdD,SDD,SDD,fdag(T2, SDD),SdD,SdD,SDD,T2,SDD,
	E1,E2,E3,E4,E5,E6)
	return result
end