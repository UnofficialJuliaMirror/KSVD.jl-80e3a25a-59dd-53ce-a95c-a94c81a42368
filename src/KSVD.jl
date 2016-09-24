module KSVD

# This is an implementation of the K-SVD algorithm.
# The original paper:
# K-SVD: An Algorithm for Designing Overcomplete Dictionaries
# for Sparse Representation
# http://www.cs.technion.ac.il/~freddy/papers/120.pdf

# Variable names are based on the original paper.
# If you try to read the code, I recommend you to see Figure 2 first.
#

export ksvd, matching_pursuit

using ProgressMeter


include("matching_pursuit.jl")

default_max_iter = 200
default_max_iter_mp = 200

srand(1234)  # for stability of tests


function error_matrix(Y::Matrix, D::Matrix, X::Matrix, k::Int)
    Eₖ = Y
    for j in 1:size(D, 2)
        if j != k
            Eₖ -= D[:, j] * X[j, :]
        end
    end
    return Eₖ
end


function init_dictionary(n::Int, K::Int)
    # D must be a rank-n matrix
    assert(n <= K)
    D = rand(n, K)
    while rank(D) != n
        D = rand(n, K)
    end

    for k in 1:K
        D[:, k] /= norm(D[:, k])
    end
    return D
end


function ksvd(Y::Matrix, D::Matrix, X::Matrix)
    N = size(Y, 2)
    for k in 1:size(X, 1)
        xₖ = X[k, :]
        # ignore if the k-th row is zeros
        if all(xₖ .== 0)
            continue
        end

        # wₖ is the column indices where the k-th row of xₖ is non-zero,
        # which is equivalent to [i for i in N if xₖ[i] != 0]
        _, wₖ, _ = findnz(xₖ)

        # Eₖ * Ωₖ implies a selection of error columns that
        # correspond to examples that use the atom D[:, k]
        Eₖ = error_matrix(Y, D, X, k)
        Ωₖ = sparse(wₖ, 1:length(wₖ), ones(length(wₖ)), N, length(wₖ))
        # Note that S is a vector that contains diagonal elements of
        # a matrix Δ such that Eₖ * Ωₖ == U * Δ * V.
        # Non-zero entries of X are set to
        # the first column of V multiplied by Δ(1, 1)
        U, S, V = svd(Eₖ * Ωₖ, thin=false)  # TODO try thin = false
        D[:, k] = U[:, 1]
        X[k, wₖ] = V[:, 1] * S[1]
    end
    return D, X
end


function ksvd(Y::Matrix, n_atoms::Int;
              tolerance = nothing,  # TODO change the name
              max_iter::Int = default_max_iter,
              max_iter_mp::Int = default_max_iter_mp)
    """
    K-SVD designs the most efficient dictionary D.
    """

    K = n_atoms
    n, N = size(Y)

    if K < n
        throw(ArgumentError("size(Y, 1) must be >= K"))
    end

    if max_iter <= 0
        throw(ArgumentError("`max_iter` must be > 0"))
    end

    if tolerance == nothing
        tolerance = ceil(K*n/2)
        tolerance = Int(tolerance)
    end

    if tolerance <= 0
        throw(ArgumentError("`tolerance` must be > 0"))
    end

    # D is a dictionary matrix that contains atoms for columns.
    D = init_dictionary(n, K)  # size(D) == (n, K)

    X = spzeros(K, N)
    @showprogress for i in 1:max_iter
        X_sparse = matching_pursuit(Y, D, max_iter = max_iter_mp)
        D, X = ksvd(Y, D, full(X_sparse))

        # return if the number of non-zero entries are <= tolerance
        if sum(X .!= 0) <= tolerance
            return D, X
        end
    end
    return D, X
end

end # module
