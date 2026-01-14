module monte_carlo

export init_compute_cluster


using Distributed
using Molly, CUDA, Unitful

include("asyn_md.jl")
using .Asyn_MD

function init_compute_cluster()
    num_gpus = length(CUDA.devices())
    tasks = Vector{Future}()
    print("ok")
    for (i, dev_id) in enumerate(0:num_gpus-1)
        w = workers()[i]

        t = @spawnat w begin
            CUDA.device!(dev_id)
            s, sm = Asyn_MD.setup_system()
            Base.invokelatest() do
                Core.eval(Main, quote
                    global sys = $s
                    global sim = $sm
                    Molly.simulate!(sys, sim, 5_000_000)
                end)
            end
        end

        push!(tasks, t)
    end

    return tasks
end


end # module
