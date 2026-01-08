module monte_carlo
#=======================#

using Molly, CUDA, Unitful

export run_simulation

struct ProgressLogger
    n_steps::Int
    lock::ReentrantLock
end

# 2. Выносим метод на уровень модуля
function Molly.log_property!(logger::ProgressLogger, sys, buffers, neighbors, step_n; kwargs...)
    if step_n % logger.n_steps == 0
        # Полезно добавить ustrip или форматирование, чтобы не спамить лишним
        lock(logger.lock) do
            println("Шаг $step_n: Энергия = ", potential_energy(sys, neighbors))
        end
    end
end

function run_simulation()

    sim_lock = ReentrantLock()

    data_dir = joinpath(dirname(pathof(Molly)), "..", "data")
    T = Float32

    ff = MolecularForceField(
        T,
        joinpath(data_dir, "force_fields", "ff99SBildn.xml"),
        joinpath(data_dir, "force_fields", "tip3p_standard.xml"),
    )

    sys = System(
        joinpath(data_dir, "6mrr_equil.pdb"),
        ff;
        nonbonded_method=:pme,
        loggers=(
            progress=ProgressLogger(1000, ReentrantLock()),
            energy=TotalEnergyLogger(1000),
            writer=TrajectoryWriter(1000, "traj_6mrr_5ps.dcd"),
        ),
        array_type=CuArray, # Теперь это сработает в рантайме
    )

    minimizer = SteepestDescentMinimizer()
    simulate!(sys, minimizer)

    temp = T(298.0) * u"K"
    random_velocities!(sys, temp)
    simulator = Langevin(
        dt=T(0.001) * u"ps",
        temperature=temp,
        friction=T(1.0) * u"ps^-1",
        coupling=MonteCarloBarostat(T(1.0) * u"bar", temp, sys.boundary),
    )

    simulate!(sys, simulator, 20_000)

    println("Simulation finished!!!")
    return sys
end

#=======================Module monte_carlo=#
end
