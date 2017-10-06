# TensorMap & Tensor:
# general tensor implementation with arbitrary symmetries
#==========================================================#
struct TensorMap{S<:IndexSpace, N₁, N₂, A, F₁, F₂} <: AbstractTensorMap{S, N₁, N₂}
    data::A
    codom::ProductSpace{S,N₁}
    dom::ProductSpace{S,N₂}
    rowr::Dict{F₁,UnitRange{Int}}
    colr::Dict{F₂,UnitRange{Int}}
    function TensorMap{S,N₁,N₂}(data, spaces::TensorMapSpace{S,N₁,N₂}) where {S<:IndexSpace, N₁, N₂}
        codom = spaces[2]
        dom = spaces[1]
        G = sectortype(S)
        if G == Trivial
            data2 = validatedata(data, codom, dom, fieldtype(S), sectortype(S))
            new{S,N₁,N₂,typeof(data2), Void, Void}(data2, codom, dom)
        else
            F₁ = fusiontreetype(G,Val(N₁))
            F₂ = fusiontreetype(G,Val(N₂))
            data2, rowr, colr = validatedata(data, codom, dom, fieldtype(S), sectortype(S))
            new{S,N₁,N₂,typeof(data2),F₁,F₂}(data2, codom, dom, rowr, colr)
        end
    end
end

const Tensor{S<:IndexSpace, N, A, F₁, F₂} = TensorMap{S, N, 0, A, F₁, F₂}

blocksectors(t::TensorMap{<:IndexSpace, N₁, N₂, <:AbstractArray}) where {N₁,N₂} = (Trivial(),)
blocksectors(t::TensorMap{<:IndexSpace, N₁, N₂, <:Associative}) where {N₁,N₂} = keys(t.data)

function blocksectors(codom::ProductSpace{S,N₁}, dom::ProductSpace{S,N₂}) where {S,N₁,N₂}
    G = sectortype(S)
    if G == Trivial
        return (Trivial(),)
    end
    if N₁ == 0
        c1 = Set{G}((one(G),))
    elseif N₁ == 1
        c1 = Set{G}(first(s) for s in sectors(codom))
    else
        c1 = foldl(union!, Set{G}(), (⊗(s...) for s in sectors(codom)))
    end
    if N₂ == 0
        c2 = Set{G}((one(G),))
    elseif N₂ == 1
        c2 = Set{G}(first(s) for s in sectors(dom))
    else
        c2 = foldl(union!, Set{G}(), (⊗(s...) for s in sectors(dom)))
    end

    return intersect(c1,c2)
end
function validatedata(data::AbstractArray, codom, dom, k::Field, ::Type{Trivial})
    if ndims(data) == 2
        size(data) == (dim(codom), dim(dom)) || size(data) == (dims(codom.spaces)..., dims(dom.spaces)...) || throw(DimensionMismatch())
    elseif ndims(data) == 1
        length(data) == dim(codom) * dim(dom) || throw(DimensionMismatch())
    else
        size(data) == (dims(codom.spaces)..., dims(dom.spaces)...) || throw(DimensionMismatch())
    end
    eltype(data) ⊆ k || warn("eltype(data) = $(eltype(data)) ⊈ $k)")
    return reshape(data, (dim(codom), dim(dom)))
end
function validatedata(data::Associative{G, <:AbstractMatrix}, codom::ProductSpace{S,N₁}, dom::ProductSpace{S,N₂}, k::Field, ::Type{G}) where {S<:IndexSpace, G<:Sector, N₁,N₂}
    F₁ = fusiontreetype(G,Val(N₁))
    F₂ = fusiontreetype(G,Val(N₂))
    rowr = Dict{F₁, UnitRange{Int}}()
    colr = Dict{F₂, UnitRange{Int}}()
    for c in blocksectors(codom, dom)
        offset1 = 0
        for s1 in sectors(codom)
            for f in fusiontrees(s1, c)
                r = offset1 .+ (1:dim(codom, s1))
                rowr[f] = r
                offset1 = last(r)
            end
        end
        offset2 = 0
        for s2 in sectors(dom)
            for f in fusiontrees(s2, c)
                r = offset2 .+ (1:dim(dom, s2))
                colr[f] = r
                offset2 = last(r)
            end
        end
        (haskey(data, c) && size(data[c]) == (offset1, offset2)) || throw(DimensionMismatch())
        eltype(data[c]) ⊆ k || warn("eltype(data) = $(eltype(data)) ⊈ $k)")
    end
    return data, rowr, colr
end
# TODO: allow to start from full data (a single AbstractArray) and create the dictionary, in the first place for Abelian sectors, or for e.g. SU₂ using Wigner 3j symbols

# Basic methods for characterising a tensor:
#--------------------------------------------
codomain(t::TensorMap) = t.codom
domain(t::TensorMap) = t.dom
space(t::TensorMap{<:Number,<:IndexSpace,N₁}, n::Int) where {N₁} = n < N₁ ? t.codom[n] : dual(t.dom[n-N₁])

Base.eltype(::Type{TensorMap{<:IndexSpace,N₁,N₂,<:AbstractArray{T}}}) where {T,N₁,N₂} = T
Base.eltype(::Type{TensorMap{<:IndexSpace,N₁,N₂,<:Associative{<:Any,<:AbstractArray{T}}}}) where {T,N₁,N₂} = T

Base.length(t::TensorMap) = sum(length, blocks(t)) # total number of free parameters, in order to use e.g. KrylovKit

# General TensorMap constructors
#--------------------------------
# with data
TensorMap(data::Union{AbstractArray,Associative}, P::TensorMapSpace{S,N₁,N₂}) where {S<:IndexSpace, N₁, N₂} = TensorMap{S,N₁,N₂}(data, P)

# without data: generic constructor from callable:
TensorMap(f, T::Type{<:Number}, P::TensorMapSpace) = TensorMap(generatedata(f, T, P.second, P.first), P)
TensorMap(f, P::TensorMapSpace) = TensorMap(generatedata(f, P.second, P.first), P)

# uninitialized tensor
TensorMap(T::Type{<:Number}, P::TensorMapSpace) = TensorMap(generatedata(Array{T}, P.second, P.first), P)
TensorMap(P::TensorMapSpace) = TensorMap(Float64, P)

Tensor(dataorf, T::Type{<:Number}, P::TensorSpace{S}) where {S<:IndexSpace} = TensorMap(dataorf, T, one(P)→P)
Tensor(dataorf, P::TensorSpace{S}) where {S<:IndexSpace} = TensorMap(dataorf, one(P)→P)
Tensor(T::Type{<:Number}, P::TensorSpace{S}) where {S<:IndexSpace} = TensorMap(T, one(P)→P)
Tensor(P::TensorSpace{S}) where {S<:IndexSpace} = TensorMap(one(P)→P)

# generate data:
generatedata(A::Type{<:AbstractArray}, T::Type{<:Number}, codom::ProductSpace, dom::ProductSpace) = _generatedata(A{T}, codom, dom, sectortype(codom))
generatedata(f, T::Type{<:Number}, codom::ProductSpace, dom::ProductSpace) = _generatedata(f, T, codom, dom, sectortype(codom))
generatedata(f, codom::ProductSpace, dom::ProductSpace) = _generatedata(f, codom, dom, sectortype(codom))

_generatedata(f, T::Type{<:Number}, codom::ProductSpace, dom::ProductSpace, ::Type{Trivial}) = f(T, (dim(codom), dim(dom)))
_generatedata(f, codom::ProductSpace, dom::ProductSpace, ::Type{Trivial}) = f((dim(codom), dim(dom)))

function _generatedata(f, T::Type{<:Number}, codom::ProductSpace{S,N₁}, dom::ProductSpace{S,N₂}, G::Type{<:Sector}) where {S,N₁,N₂}
    F₁ = fusiontreetype(G, Val(N₁))
    F₂ = fusiontreetype(G, Val(N₂))
    rowr = Dict{F₁, UnitRange{Int}}()
    colr = Dict{F₂, UnitRange{Int}}()
    A = typeof(f(T,(1,1)))
    data = Dict{G,A}()
    for c in blocksectors(codom, dom)
        dim1 = 0
        for s1 in sectors(codom)
            for f1 in fusiontrees(s1, c)
                r = dim1 .+ (1:dim(codom, s1))
                dim1 = last(r)
                rowr[f1] = r
            end
        end
        dim2 = 0
        for s2 in sectors(dom)
            for f2 in fusiontrees(s2, c)
                r = dim2 .+ (1:dim(dom, s2))
                dim2 = last(r)
                colr[f2] = r
            end
        end
        data[c] = f(T, (dim1, dim2))
    end
    return data
end
function _generatedata(f, codom::ProductSpace{S,N₁}, dom::ProductSpace{S,N₂}, G::Type{<:Sector}) where {S,N₁,N₂}
    F₁ = fusiontreetype(G, Val(N₁))
    F₂ = fusiontreetype(G, Val(N₂))
    rowr = Dict{F₁, UnitRange{Int}}()
    colr = Dict{F₂, UnitRange{Int}}()
    A = typeof(f((1,1)))
    data = Dict{G,A}()
    for c in blocksectors(codom, dom)
        dim1 = 0
        for s1 in sectors(codom)
            for f1 in fusiontrees(s1, c)
                r = dim1 .+ (1:dim(codom, s1))
                dim1 = last(r)
                rowr[f1] = r
            end
        end
        dim2 = 0
        for s2 in sectors(dom)
            for f2 in fusiontrees(s2, c)
                r = dim2 .+ (1:dim(dom, s2))
                dim2 = last(r)
                colr[f2] = r
            end
        end
        data[c] = f((dim1, dim2))
    end
    return data
end

# Getting and setting the data
#------------------------------
hasblock(t::TensorMap{<:ElementarySpace,N₁,N₂,<:Associative}, s::Sector) where {N₁,N₂} = haskey(t.data, s)
hasblock(t::TensorMap{<:ElementarySpace,N₁,N₂,<:AbstractArray}, ::Trivial) where {N₁,N₂} = true

block(t::TensorMap{S,N₁,N₂,<:Associative}, s::Sector) where {S,N₁,N₂} = sectortype(S) == typeof(s) ? t.data[s] : throw(SectorMismatch())
block(t::TensorMap{S,N₁,N₂,<:AbstractArray}, ::Trivial) where {S,N₁,N₂} = t.data

blocks(t::TensorMap{S,N₁,N₂,<:Associative}) where {S,N₁,N₂} = values(t.data)
blocks(t::TensorMap{S,N₁,N₂,<:AbstractArray}) where {S,N₁,N₂} = (t.data,)

function Base.getindex(t::TensorMap{S,N₁,N₂}, f1::FusionTree{G,N₁}, f2::FusionTree{G,N₂}) where {S,N₁,N₂,G}
    c = f1.incoming
    c == f2.incoming || throw(SectorMismatch())
    checksectors(codomain(t), f1.outgoing) && checksectors(domain(t), f2.outgoing)
    return splitdims(view(t.data[c], t.rowr[f1], t.colr[f2]), dims(codomain(t), f1.outgoing), dims(domain(t), f2.outgoing))
end
Base.setindex!(t::TensorMap{S,N₁,N₂}, v, f1::FusionTree{G,N₁}, f2::FusionTree{G,N₂}) where {S,N₁,N₂,G} = copy!(getindex(t, f1, f2), v)

function Base.getindex(t::Tensor{S,N}, f::FusionTree{G,N}) where {S,N,G}
    f.incoming == one(G) || throw(SectorMismatch())
    checksectors(codomain(t), f.outgoing)
    return splitdims(view(t.data[one(G)], t.rowr[f], :), dims(codomain(t), f.outgoing), ())
end
Base.setindex!(t::TensorMap{S,N}, v, f::FusionTree{G,N}) where {S,N,G} = copy!(getindex(t, f), v)

# For a tensor with trivial symmetry, allow direct indexing
@inline Base.getindex(t::TensorMap{<:Any,N₁,N₂,<:AbstractArray}) where {N₁,N₂} = splitdims(t.data, dims(codomain(t)), dims(domain(t)))
@inline function Base.getindex(t::TensorMap{<:Any,N₁,N₂,<:AbstractArray}, I::Vararg{Int}) where {N₁,N₂}
    data = splitdims(t.data, dims(codom), dims(dom))
    @boundscheck checkbounds(data, I)
    @inbounds v = data[I...]
    return v
end
@inline function Base.setindex!(t::TensorMap{<:Any,N₁,N₂,<:AbstractArray}, v, I::Vararg{Int}) where {N₁,N₂}
    data = splitdims(t.data, dims(codom), dims(dom))
    @boundscheck checkbounds(data, I)
    @inbounds data[I...] = v
    return v
end

# Similar
#---------
Base.similar(t::TensorMap{S}, ::Type{T}, P::TensorMapSpace{S} = (domain(t)=>codomain(t))) where {T,S} = TensorMap(d->similar(first(blocks(t)), T, d), P)
Base.similar(t::TensorMap{S}, ::Type{T}, P::TensorSpace{S}) where {T,S} = Tensor(d->similar(first(blocks(t)), T, d), P)
Base.similar(t::TensorMap{S}, P::TensorMapSpace{S} = (domain(t)=>codomain(t))) where {S} = TensorMap(d->similar(first(blocks(t)), d), P)
Base.similar(t::TensorMap{S}, P::TensorSpace{S}) where {S} = Tensor(d->similar(first(blocks(t)), d), P)

# Copy and fill tensors:
# ------------------------
function Base.copy!(tdest::TensorMap, tsource::TensorMap)
    codomain(tdest) == codomain(tsource) && domain(tdest) == domain(tsource) || throw(SpaceError())
    for c in blocksectors(tdest)
        copy!(block(tdest, c), block(tsource, c))
    end
    return tdest
end
function Base.fill!(t::TensorMap, value::Number)
    for b in blocks(t)
        fill!(b, value)
    end
    return t
end

#
# # Conversion and promotion:
# #---------------------------
# Base.promote_rule(::Type{<:TensorMap{T1,S}},::Type{<:TensorMap{T2,S}}) where {T1, T2, S} = TensorMap{promote_type(T1,T2),S}
#
# Base.convert(::Type{TensorMap{T,S}}, t::Tensor{T,S}) where {T,S} = t
# Base.convert(::Type{TensorMap{T1,S}}, t::Tensor{T2,S}) where {T1,T2,S} = copy!(similar(t, T1), t)

# TODO: Check whether we need anything of this old stuff
# Base.promote_rule{S,T1,T2,N1,N2}(::Type{Tensor{S,T1,N1}},::Type{Tensor{S,T2,N2}})=Tensor{S,promote_type(T1,T2)}
# Base.promote_rule{S,T1,T2}(::Type{Tensor{S,T1}},::Type{Tensor{S,T2}})=Tensor{S,promote_type(T1,T2)}
#
# Base.promote_rule{S,T1,T2,N}(::Type{AbstractTensor{S,ProductSpace,T1,N}},::Type{Tensor{S,T2,N}})=AbstractTensor{S,ProductSpace,promote_type(T1,T2),N}
# Base.promote_rule{S,T1,T2,N1,N2}(::Type{AbstractTensor{S,ProductSpace,T1,N1}},::Type{Tensor{S,T2,N2}})=AbstractTensor{S,ProductSpace,promote_type(T1,T2)}
# Base.promote_rule{S,T1,T2}(::Type{AbstractTensor{S,ProductSpace,T1}},::Type{Tensor{S,T2}})=AbstractTensor{S,ProductSpace,promote_type(T1,T2)}


# Base.convert{S,T,N}(::Type{Tensor{S,T,N}},t::Tensor{S,T,N})=t
# Base.convert{S,T1,T2,N}(::Type{Tensor{S,T1,N}},t::Tensor{S,T2,N})=copy!(similar(t,T1),t)
# Base.convert{S,T}(::Type{Tensor{S,T}},t::Tensor{S,T})=t
# Base.convert{S,T1,T2}(::Type{Tensor{S,T1}},t::Tensor{S,T2})=copy!(similar(t,T1),t)
#
# Base.float{S,T<:FloatingPoint}(t::Tensor{S,T})=t
# Base.float(t::Tensor)=tensor(float(t.data),space(t))
#
# Base.real{S,T<:Real}(t::Tensor{S,T})=t
# Base.real(t::Tensor)=tensor(real(t.data),space(t))
# Base.complex{S,T<:Complex}(t::Tensor{S,T})=t
# Base.complex(t::Tensor)=tensor(complex(t.data),space(t))
#
# for (f,T) in ((:float32,    Float32),
#               (:float64,    Float64),
#               (:complex64,  Complex64),
#               (:complex128, Complex128))
#     @eval (Base.$f){S}(t::Tensor{S,$T}) = t
#     @eval (Base.$f)(t::Tensor) = tensor(($f)(t.data),space(t))
# end
#
# Basic vector space methods:
# ---------------------------
function Base.scale!(t1::TensorMap, t2::TensorMap, α::Number)
    (codomain(t1)==codomain(t2) && domain(t1) == domain(t2)) || throw(SpaceError())
    for c in blocksectors(t1)
        block(t1, c) .= α .* block(t2, c)
    end
    return t1
end

function add!(t1::TensorMap, α::Number, t2::TensorMap, β::Number)
    (codomain(t1)==codomain(t2) && domain(t1) == domain(t2)) || throw(SpaceError())
    for c in blocksectors(t1)
        block(t1, c) .= α .* block(t1, c) + β .* block(t2, c)
    end
    return t1
end

function Base.vecdot(t1::TensorMap, t2::TensorMap)
    (codomain(t1) == codomain(t2) && domain(t1) == domain(t2)) || throw(SpaceMismatch())
    return sum(dim(c)*vecdot(block(t1,c), block(t2,c)) for c in blocksectors(t1))
end

Base.vecnorm(t::TensorMap, p::Real) = vecnorm((dim(c)^(1/p)*vecnorm(block(t,c), p) for c in blocksectors(t)), p)

# Basic algebra and factorization methods:
#-----------------------------------------
function mul!(tC::TensorMap, β::Number, tA::TensorMap,  tB::TensorMap, α::Number)
    (codomain(tC) == codomain(tA) && domain(tC) == domain(tB) && domain(tA) == codomain(tB)) || throw(SpaceMismatch())
    if sectortype(tC) == Trivial
        mul!(block(tC, Trivial()), β, block(tA, Trivial()), block(tB, Trivial()), α)
    else
        for c in blocksectors(tC)
            if hasblock(tA, c) # then also tB should have such a block
                mul!(block(tC, c), β, block(tA, c), block(tB, c), α)
            elseif β == 0
                fill!(block(tC, c), 0)
            elseif β != 1
                scale!(block(tC, c), β)
            end
        end
    end
    return tC
end
function leftorth!(t::TensorMap{S}) where {S<:ElementarySpace}
    if isa(t.data, AbstractArray)
        Q, R = qrpos!(t.data)
        V = S(size(Q,2))
        return TensorMap(Q, codomain(t)←V), TensorMap(R, V←domain(t))
    else
        it = blocksectors(t)
        c, s = next(it, start(it))
        Q,R = qrpos!(t.data[c])
        Qdata = Dict(c => Q)
        Rdata = Dict(c => R)
        while !done(it, s)
            c, s = next(it, s)
            Qdata[c], Rdata[c] = qrpos!(t.data[c])
        end
        V = S((c=>size(Qdata[c], 2) for c in it)...)
        return TensorMap(Qdata, codomain(t)←V), TensorMap(Rdata, V←domain(t))
    end
end
function rightorth!(t::TensorMap{S}) where {S<:ElementarySpace}
    if isa(t.data, AbstractArray)
        L, Q = lqpos!(t.data)
        V = S(size(Q,1))
        return TensorMap(L, codomain(t)←V), TensorMap(Q, V←domain(t))
    else
        it = blocksectors(t)
        c, s = next(it, start(it))
        L, Q = lqpos!(t.data[c])
        Ldata = Dict(c => L)
        Qdata = Dict(c => Q)
        while !done(it, s)
            c, s = next(it, s)
            Ldata[c], Qdata[c] = lqpos!(t.data[c])
        end
        V = S((c=>size(Qdata[c], 1) for c in it)...)
        return TensorMap(Ldata, codomain(t)←V), TensorMap(Qdata, V←domain(t))
    end
end
function svd!(t::TensorMap{S}, trunc::TruncationScheme = NoTruncation()) where {S<:ElementarySpace}
    if isa(t.data, AbstractArray)
        U,Σ,V = svd!(t.data)
        dmax = length(Σ)
        if isa(trunc, TruncationError)
            p = trunc.p
            normΣ = vecnorm(Σ, p)
            dtrunc = dmax
            while true
                dtrunc -= 1
                if vecnorm(view(Σ, dtrunc+1:dmax), p) / normΣ > trunc.ϵ
                    dtrunc += 1
                    break
                end
            end
        elseif isa(trunc, TruncationDimension)
            dtrunc = min(d, trunc.dim)
        else
            error("unknown truncation scheme")
        end
        truncnorm = vecnorm(view(Σ, dtrunc+1:dmax), p)
        W = S(dtrunc)
        if dtrunc < dmax
            U = U[:,1:d]
            V = V[1:d,:]
            Σ = Σ[1:d]
        end
        return TensorMap(U, codomain(t)←W), TensorMap(Diagonal(Σ), W←W), TensorMap(W, W←domain(t)), normΣ, truncnorm
    else
        it = blocksectors(t)
        c, s = next(it, start(it))
        U,Σ,V = svd!(t.data[c])
        Udata = Dict(c => U)
        Σdata = Dict(c => Diagonal(Σ))
        Vdata = Dict(c => V)
        maxdim = Dict(c=> length(Σ))
        truncdim = Dict(c=> length(Σ))
        while !done(it, s)
            c, s = next(it, s)
            U,Σ,V = svd!(t.data)
            Udata[c] = U
            Σdata[c] = Σ
            Vdata[c] = V
            dmax[c] = length(Σ)
            dtrunc[c] = length(Σ)
        end

        normΣ = vecnorm(sqrt(dim(c))*vecnorm(Σdata[c]) for c in it)
        if isa(trunc, NoTruncation)
            # don't do anything
        elseif isa(trunc, TruncationError)
            p = trunc.p
            while true
                cmin = mininum(c->sqrt(dim(c))*Σdata[c][dtrunc[c]], it)
                dtrunc[cmin] -= 1
                truncnorm = vecnorm((dim(c)*vecnorm(view(Σdata[c],dtrunc[c]+1:dmax[c]), p) for c in it), p)
                if truncnorm/normΣ > trunc.ϵ
                    dtrunc[cmin] += 1
                    break
                end
            end
        elseif isa(trunc, TruncationDimension)
            while sum(c->dim(c)*dtrunc[c], it) > trunc.dim
                cmin = mininum(c->sqrt(dim(c))*Σdata[c][dtrunc[c]], it)
                dtrunc[cmin] -= 1
            end
        elseif isa(trunc, TruncationSpace)
            for c in it
                dtrunc[c] = min(dtrunc[c], dim(trunc.space, c))
            end
        else
            error("unknown truncation scheme")
        end
        truncnorm = vecnorm(sqrt(dim(c))*vecnorm(view(Σdata[c],dtrunc[c]+1:dmax[c])) for c in it)

        for c in it
            if dtrunc[c] != dmax[c]
                Udata[c] = Udata[c][:,1:dtrunc[c]]
                Vdata[c] = Vdata[c][1:dtrunc[c],:]
                Σdata[c] = Σdata[c][1:dtrunc[c]]
            end
        end
        V = S(dtrunc)
        return TensorMap(Udata, codomain(t)←V), TensorMap(Dict(c=>Diagonal(Σdata[c]) for c in it), V←V), TensorMap(Vdata, V←domain(t)), normΣ, truncnorm
    end
end

# Index manipulations
#---------------------
using Base.Iterators.filter
fusiontrees(t::TensorMap) = filter(fs->(fs[1].incoming == fs[2].incoming), product(keys(t.rowr), keys(t.colr)))

function repartitionind!(tdst::TensorMap{S,N₁,N₂}, tsrc::TensorMap{S,N₁′,N₂′}) where {S,N₁,N₂,N₁′,N₂′}
    space1 = codomain(tdst) ⊗ dual(domain(tdst))
    space2 = codomain(tsrc) ⊗ dual(domain(tsrc))
    space1 == space2 || throw(SpaceMismatch())
    p = (ntuple(n->n, Val{N₁′})..., ntuple(n->N₁′+N₂′+1-n, Val{N₂′}))
    p1 = tselect(p, ntuple(n->n, Val{N₁}))
    p2 = reverse(tselect(p, ntuple(n->N₁+n, Val{N₂})))
    pdata = (p1..., p2...)

    if sectortype(S) == Trivial
        tdst[] .= permutedims(tsrc[], pdata)
    else
        fill!(tdst, 0)
        for (f1,f2) in fusiontrees(t)
            for ((f1′,f2′), coeff) in repartition(f1, f2, Val{N₁})
                tdst[f1′,f2′] .+= coeff .* permutedims(tsrc[f1,f2], pdata)
            end
        end
    end
    return tdst
end

function permuteind!(tdst::TensorMap{S,N₁,N₂}, tsrc::TensorMap{S}, p1::NTuple{N₁,Int}, p2::NTuple{N₂,Int} = ()) where {S,N₁,N₂}
    # TODO: Frobenius-Schur indicators!, and fermions!
    space1 = codomain(tdst) ⊗ dual(domain(tdst))
    space2 = codomain(tsrc) ⊗ dual(domain(tsrc))

    N₁′, N₂′ = length(codomain(tsrc)), length(domain(tsrc))
    p = linearizepermutation(p1, p2, N₁′, N₂′)

    isperm(p) && length(p) == N₁′+N₂′ || throw(ArgumentError("not a valid permutation: $p1 & $p2"))
    space1 == space2[p] || throw(SpaceMismatch())

    pdata = (p1..., p2...)
    if sectortype(S) == Trivial
        tdst[] .= permutedims(tsrc[], pdata)
    else
        fill!(tdst, 0)
        for (f1,f2) in fusiontrees(tsrc)
            for ((f1′,f2′), coeff) in permute(f1, f2, p1, p2)
                tdst[f1′,f2′] .+= coeff .* permutedims(tsrc[f1,f2], pdata)
            end
        end
    end
    return tdst
end

# do we need those?
function splitind! end#

function fuseind! end
