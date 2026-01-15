module S_MD


export setup_system

using CUDA, Molly, Unitful

# struct ProgressLogger
#     n_steps::Int
# end

# Убираем ReentrantLock для воркеров, так как у каждого свой поток вывода
# function Molly.log_property!(logger::ProgressLogger, sys, buffers, neighbors, step_n; kwargs...)
#     if step_n % logger.n_steps == 0
#         println("GPU $(device()): Шаг $step_n")
#     end
# end

function setup_system()
    #device!(dev_id) # Сначала выбираем карту!

    data_dir = joinpath(dirname(pathof(Molly)), "..", "data")
    T = Float32

    ff = MolecularForceField(T,
        joinpath(data_dir, "force_fields", "ff99SBildn.xml"),
        joinpath(data_dir, "force_fields", "tip3p_standard.xml")
    )

    sys = System(
        joinpath(data_dir, "6mrr_equil.pdb"),
        ff;
        nonbonded_method=:pme,
        loggers=(
            energy=TotalEnergyLogger(10),
        ),
        array_type=CuArray, # Это создаст CuArray на выбранном device!(dev_id)
    )
    simulate!(sys, SteepestDescentMinimizer())

    temp = T(298.0) * u"K"
    random_velocities!(sys, temp)
    simulator = Langevin(
        dt=T(0.001) * u"ps",
        temperature=temp,
        friction=T(1.0) * u"ps^-1",
    )

    return sys, simulator
end #setup_system


end # module
