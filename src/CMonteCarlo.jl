module CMonteCarlo


export monsystemsetup

using Molly
# using CUDA
using Unitful
using StaticArrays
using Graphs
include("ChemTools.jl")
using .ChemTools: smilesmol
include("DMonteCarlo.jl")
using .DMonteCarlo


function metrosimula(sys, rotse, temperature)
    trialargs = Dict(
        :rots => rotse,
        :mangle => 0.2u"rad" # 0.2 Максимальный шаг
    )

    sim = MetropolisMonteCarlo(
        temperature=temperature,
        trial_moves=rotmove!,
        trial_args=trialargs,
    )
    return sim
end


function monsystemsetup(smilese; singlmode=true, box_size=10.0u"nm", temperature=298.15u"K")
    aindexes, charges, atypes, vdwe, coords, bonds, torsionic, bharmonics, aharmonics, rbonds = smilesmol(smilese)
    natoms = length(aindexes)

    # 1. Массы
    const_amasses = Dict(
        1 => 1.008, 6 => 12.011, 7 => 14.007, 8 => 15.999, 16 => 32.06
    )

    # заряды без единиц измерения (реализация неявной воды в моле безкулоновская)
    atoms = [
        Molly.Atom(
            index=i,
            charge=charges[i],
            mass=const_amasses[Int16(atypes[i])] * u"g/mol",
            σ=vdwe[i][1] * u"nm",
            ϵ=vdwe[i][2] * u"kJ/mol"
        ) for i in aindexes
    ]

    # 2. Скорости (Float32 nm/ps)
    velocities = [zeros(SVector{3,Float32}) * u"nm/ps" for _ in 1:natoms]

    # 3. Границы. box_size уже с юнитами nm по умолчанию.
    boundary = CubicBoundary(box_size)

    # 4. Взаимодействия с казанием использовать список соседей
    vdw = LennardJones(
        cutoff=DistanceCutoff(4.0u"nm"),
        use_neighbors=true,
        weight_special=0.5
    )

    electrostatics = Coulomb(
        cutoff=DistanceCutoff(4.0u"nm"),
        use_neighbors=true,
        weight_special=0.8333,
        coulomb_const=138.9354558u"kJ * nm * mol^-1"
    )

    # 5. Топологи
    moltopo = MolecularTopology(
        fill(1, natoms),
        [natoms],
        bonds
    )

    # 6. 1-2 1-3 1-4
    moltree = SimpleGraph(natoms)
    for (i, j) in bonds
        add_edge!(moltree, i, j)
    end

    eligible = trues(natoms, natoms)
    special = falses(natoms, natoms)

    for i in 1:natoms
        eligible[i, i] = false
        # 1-2
        for n2 in neighbors(moltree, i)
            eligible[n2, i] = false
            eligible[i, n2] = false
            # 1-3
            for n3 in neighbors(moltree, n2)
                eligible[n3, i] = false
                eligible[i, n3] = false
                # 1-4
                for n4 in neighbors(moltree, n3)
                    special[n4, i] = true
                    special[i, n4] = true
                end
            end
        end
    end

    # 7. Группы разворота и дополненая четвёрка поворота для cv
    rots = []
    cvtorsions = NTuple{4,Int16}[]
    numsegments = length(connected_components(moltree))
    for tbond in rbonds
        u, v = tbond
        rem_edge!(moltree, tbond...)
        comps = connected_components(moltree)
        if numsegments == length(comps) - 1
            push!(cvtorsions, (neighbors(moltree, u)[1], u, v, neighbors(moltree, v)[1]))
            iu = findfirst(c -> u in c, comps)
            iv = findfirst(c -> v in c, comps)
            if length(comps[iu]) <= length(comps[iv])
                # лучше меньшие вектора(наверное)
                push!(rots, (axis=tbond, irotatoms=comps[iu]))
            else
                push!(rots, (axis=(v, u), irotatoms=comps[iv]))
            end
        else
            println("cicle")
            #looogssss
        end
        add_edge!(moltree, tbond...)
    end

    # 8. торсионные потенциалы
    to1 = Int16[]
    to2 = Int16[]
    to3 = Int16[]
    to4 = Int16[]
    torsions = PeriodicTorsion[]
    for t in torsionic
        push!(to1, t[:indices][1])
        push!(to2, t[:indices][2])
        push!(to3, t[:indices][3])
        push!(to4, t[:indices][4])
        # Создаем торсион. N=1, так как мы берем каждое слагаемое отдельно.
        # Molly ожидает NTuple, поэтому используем (val,)

        tp = PeriodicTorsion(
            periodicities=(Int16(t[:period]),),
            phases=(t[:phase] * u"rad",),
            ks=(t[:k] * u"kJ/mol",),
            proper=true
        )
        push!(torsions, tp)
    end

    torsionsl = InteractionList4Atoms(
        to1, to2, to3, to4,
        torsions
    )

    # 9. Гармонические потенциалы по связям
    bo1, bo2 = Int16[], Int16[]
    bharmon = HarmonicBond[]
    for tharm in bharmonics
        push!(bo1, tharm[1][1] + 1)
        push!(bo2, tharm[1][2] + 1)
        push!(bharmon,
            HarmonicBond(k=tharm[2] * u"kJ/mol/nm^2", r0=tharm[3] * u"nm"))
    end

    bondharmonicl =
        InteractionList2Atoms(bo1, bo2, bharmon)
    # println(bondharmonicl)

    # 10. Гармонические потенциалы по углам 
    ao1, ao2, ao3 = Int16[], Int16[], Int16[]
    aharmon = HarmonicAngle[]
    for ang in aharmonics
        idxs = ang[1] .+ 1
        push!(ao1, idxs[1])
        push!(ao2, idxs[2])
        push!(ao3, idxs[3])

        push!(aharmon, HarmonicAngle(
            k=ang[2] * u"kJ/mol",
            θ0=ang[3] * u"rad"
        ))
    end
    angleharmonicsl =
        InteractionList3Atoms(ao1, ao2, ao3, aharmon)
    # println(angleharmonicsl)

    # 11. мета
    numcv = length(cvtorsions)
    cvstep = 0.1f0 # Шаг сетки в радианах
    hillw = 1.5f0  # Высота холма в kJ/mol
    gamma = 10.0f0
    gridcv = GridTorsionsCV{numcv}(cvtorsions, cvstep, :pbc)
    shared_memory = Dict{NTuple{numcv,Int16},Float32}()
    grid_bias = singlmode ?
                SinglSparseGridBias{numcv}(shared_memory, hillw, Float32(ustrip(temperature)), gamma) :
                AsyncSparseGridBias{numcv}(shared_memory, empty(shared_memory), hillw, Float32(ustrip(temperature)), gamma)
    metacpot = BiasPotential(gridcv, grid_bias)

    # 12. неявная вода
    # Подготовка данных для растворителя
    num_to_element = Dict(1 => "H", 6 => "C", 7 => "N", 8 => "O", 16 => "S")
    # Создаем массив объектов AtomData
    atoms_data = [
        Molly.AtomData(element=num_to_element[Int16(atypes[i])])
        for i in aindexes
    ]
    # Оборачиваем связи для GBSA
    bonds_wrapper = (is=[Int16(b[1]) for b in bonds], js=[Int16(b[2]) for b in bonds])
    # Создаем растворитель (теперь он не упадет, так как T=Float64)
    solvent = ImplicitSolventGBN2(
        atoms,
        atoms_data,
        bonds_wrapper
    )

    # 12. Сборка системы
    sys = System(
        atoms=atoms,
        coords=coords .* u"nm",
        velocities=velocities,
        topology=moltopo,
        boundary=boundary,
        pairwise_inters=(vdw, electrostatics),
        specific_inter_lists=(
            bondharmonicl,
            angleharmonicsl,
            torsionsl,
        ),
        general_inters=(metacpot, solvent),
        neighbor_finder=DistanceNeighborFinder(
            eligible=eligible,
            special=special,
            n_steps=10,
            dist_cutoff=1.2 * u"nm",
        ),
        loggers=(mc=MonteCarloLogger(),
            metac=MetadynamicsLogger(gridcv, 1, grid_bias),),
        energy_units=u"kJ/mol",
        force_units=u"kJ/mol/nm",
        k=8.314462618e-3u"kJ/mol/K",
    )

    return sys, metrosimula(sys, rots, temperature), numcv
end


end
