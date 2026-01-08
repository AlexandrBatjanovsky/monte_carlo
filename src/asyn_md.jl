module asyn_md


using Molly, CUDA, Unitful

export setup_system

function setup_system()
    data_dir = joinpath(dirname(pathof(Molly)), "..", "data")
    T = Float32
    ff = MolecularForceField(T,
        joinpath(data_dir, "force_fields", "ff99SBildn.xml"),
        joinpath(data_dir, "force_fields", "tip3p_standard.xml")
    )

    # Создаем систему
    sys = System(
        joinpath(data_dir, "6mrr_equil.pdb"),
        ff;
        nonbonded_method=:pme,
        loggers=(
            progress=ProgressLogger(1000, ReentrantLock()),
            energy=TotalEnergyLogger(10),
        ),
        array_type=CuArray,
    )

    # Инициализируем скорости и симулятор
    temp = T(298.0) * u"K"
    random_velocities!(sys, temp)

    simulator = Langevin(
        dt=T(0.001) * u"ps",
        temperature=temp,
        friction=T(1.0) * u"ps^-1",
        coupling=MonteCarloBarostat(T(1.0) * u"bar", temp, sys.boundary),
    )

    return sys, simulator
end


#========module asyn_md===========#
end
