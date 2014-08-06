immutable TensorMap{S,P,T}<:AbstractTensorMap{S,P,T}
    tensor::AbstractTensor{S,P,T}
    codom::P
    dom::P
    function TensorMap(t::TensorMap{S,P,T},codom::P,dom::P=codom)
        t in codom ⊗ dual(dom).' || throw(SpaceError("tensor cannot represent map from $dom to $codom"))
        new(d,codom,dom)
    end
end
# properties
codomain(A::TensorMap)=codomain(A.codom)
domain(A::TensorMap)=domain(A.dom)

Base.isreal(A::TensorMap)=isreal(A.tensor)

# comparison
==(A::TensorMap,B::TensorMap)=A.map==B.map

# multiplication with vector
function Base.A_mul_B!{S,P}(y::AbstractTensor{S,P},A::TensorMap{S,P},x::AbstractTensor{S,P})
    x in domain(A) || throw(SpaceError("x in not in domain of map"))
    y in codomain(A) || throw(SpaceError("y in not in codomain of map"))
    N1=length(codomain(A))
    N2=length(domain(A))
    tensorcontract!(1,A.tensor,[-(1:N2),reverse(1:N1)],'N',x,1:N1,'N',0,y,-(1:N2))
    return y
end
function Base.Ac_mul_B!{S,P}(y::AbstractTensor{S,P},A::TensorMap{S,P},x::AbstractTensor{S,P})
    x in dual(conj(codomain(A))) || throw(SpaceError("x in not in domain of map"))
    y in dual(conj(domain(A))) || throw(SpaceError("y in not in domain of map"))
    N1=length(codomain(A))
    N2=length(domain(A))
    tensorcontract!(1,A.tensor,[(1:N2),-reverse(1:N1)],'C',x,1:N2,'N',0,y,-(1:N1))
    return y
end
function Base.At_mul_B!{S,P}(y::AbstractTensor{S,P},A::TensorMap{S,P},x::AbstractTensor{S,P})
    x in dual(codomain(A)) || throw(SpaceError("x in not in domain of map"))
    y in dual(domain(A)) || throw(SpaceError("y in not in domain of map"))
    N1=length(codomain(A))
    N2=length(domain(A))
    tensorcontract!(1,A.tensor,[(1:N2),-reverse(1:N1)],'N',x,1:N2,'N',0,y,-(1:N1))
    return y
end
