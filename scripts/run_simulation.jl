using Revise
using Distributed
using Molly
#include("../src/MonteCarlo.jl")
#using .MonteCarlo

MODE = "metropolis"
if MODE == "mdgpudistrib"
    using CUDA
    # Теперь CUDA видна везде в этом файле без @eval
    numgpu = length(CUDA.devices())
    if nprocs() == 1
        addprocs(numgpu)
    end
    tasks = Vector{Future}()
    @everywhere begin
        using Pkg
        Pkg.activate(".")
        using MonteCarlo, CUDA, Molly
    end

    for (i, dev_id) in enumerate(0:numgpu-1)
        w = workers()[i]

        t = @spawnat w begin
            CUDA.device!(dev_id)
            sys, sim = MonteCarlo.mdsystemsetup()
            Molly.simulate!(sys, sim, 5_000)
        end

        push!(tasks, t)
    end

elseif MODE == "metropolis"
    using Distributed
    if nprocs() == 1
        addprocs(3) # Добавляем воркеры, если они еще не добавлены
    end

    @everywhere begin
        using Pkg
        Pkg.activate(".")
        using MonteCarlo
        #include("../src/DMonteCarlo.jl")
        #using .DMonteCarlo
        using Molly
    end
    sys, mcsim = MonteCarlo.monsystemsetup("C=CCO")
    futures = [@spawnat w simulate!(sys, mcsim, 10_000_000) for w in workers()]

    # results = fetch.(futures)
end
