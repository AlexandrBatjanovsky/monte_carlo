#run_simulation.jl (в корне проекта)
using Distributed
using CUDA
using Revise
using MonteCarlo

# Сначала добавляем процессы
addprocs(length(CUDA.devices()))

# Затем загружаем зависимости на всех процессах
@everywhere begin
    using Molly, CUDA, Unitful
    include("src/SMolDyn.jl")
    # using .S_MD
end

# Теперь запускаем симуляцию
# tasks = monte_carlo.init_compute_cluster()
num_gpus = length(CUDA.devices())
tasks = Vector{Future}()
for (i, dev_id) in enumerate(0:num_gpus-1)
    w = workers()[i]
    t = @spawnat w begin
        CUDA.device!(dev_id)
        s, sm = SMolDyn.setup_system()
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

include("src/SMonteCarlo.jl")
SMonteCarlo.aa()

