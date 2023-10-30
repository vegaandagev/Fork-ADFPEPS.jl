using ADFPEPS
using ADFPEPS:double_ipeps_energy,swapgate, generate_vertical_rules, generate_horizontal_rules
using CUDA
using Random
using TeneT

CUDA.allowscalar(false)
Random.seed!(100)

 indD = [0, 1]
dimsD = [1, 1]
 indχ = [-1, 0, 1]
dimsχ = [1, 2, 1]
symmetry = :U1

ipeps,key = init_ipeps(tJ_bilayer(3.0,1.0,0.0,2.0,0.0); 
                       Ni = 2, 
                       Nj = 2, 
                 symmetry = symmetry, 
                    atype = CuArray, 
                   folder = "./example/$symmetry/",
                      tol = 1e-10, 
                  maxiter = 10, 
                  miniter = 1, 
                        D = sum(dimsD), 
                        χ = sum(dimsχ), 
                     indD = indD, 
                     indχ = indχ, 
                    dimsD = dimsD, 
                    dimsχ = dimsχ)
# consts = initial_consts(key)
# double_ipeps_energy(atype(ipeps), consts, key)
optimiseipeps(ipeps, key; 
                f_tol = 1e-10, 
               opiter = 200, 
              verbose = true)