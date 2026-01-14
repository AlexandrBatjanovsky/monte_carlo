#run_simulation.jl (в корне проекта)
using Distributed
using CUDA
using Revise

# Сначала добавляем процессы
addprocs(length(CUDA.devices()))

# Затем загружаем зависимости на всех процессах
@everywhere begin
    using Molly, CUDA, Unitful
    include("src/asyn_md.jl")
    # using .Asyn_MD
end

# Теперь запускаем симуляцию
using monte_carlo
# tasks = monte_carlo.init_compute_cluster()

