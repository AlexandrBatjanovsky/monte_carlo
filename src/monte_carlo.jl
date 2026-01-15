module monte_carlo

export init_compute_MD


using Distributed
using Molly, CUDA, Unitful

include("s_md.jl")
using .S_MD

function init_compute_MD()
    num_gpus = length(CUDA.devices())
    tasks = Vector{Future}()
    print("ok")
    for (i, dev_id) in enumerate(0:num_gpus-1)
        w = workers()[i]

        t = @spawnat w begin
            CUDA.device!(dev_id)
            s, sm = S_MD.setup_system()
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
