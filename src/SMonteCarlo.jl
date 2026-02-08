module SMonteCarlo


export monsystemsetup

using Molly
using CUDA
using Unitful
using LinearAlgebra
using StaticArrays
using Graphs
include("ChemTools.jl")
using .ChemTools: smilesmol

# cv по двугранным углам
struct GridTorsionsCV
    indices::Vector{NTuple{4,Int}}
    grid_step::Float32
    correction::Symbol
end
function Molly.calculate_cv(cv::GridTorsionsCV, coords, atoms, boundary, velocities; kwargs...)
    return map(cv.indices) do idx
        ang = torsion_angle(coords[idx[1]], coords[idx[2]], coords[idx[3]], coords[idx[4]], boundary)
        # Сразу квантуем в Int16
        return round(Int16, (ang + pi) / cv.grid_step)
    end
end

struct SparseGridBias
    data::Dict{Vector{Int16},Int16}
    W::Float32
end
function Molly.potential_energy(bias_fn::SparseGridBias, cv_sim; kwargs...)
    num_hills = get(bias_fn.data, cv_sim, Int16(0))
    return (num_hills * bias_fn.W) * u"kJ/mol"
end

struct MetadynamicsLogger
    interval::Int
    bias::SparseGridBias
end
function Molly.log_property!(logger::MetadynamicsLogger, sys, buffers, neighbors, step_n, args...; kwargs...)
    # function Molly.log_property!(logger::MetadynamicsLogger, sys, step_n; kwargs...)
    if step_n % logger.interval == 0
        # 1. Ищем наш BiasPotential
        # (Проверяем тип cv_type, чтобы не ошибиться)
        idx = findfirst(i -> i isa BiasPotential && i.cv_type isa GridTorsionsCV, sys.general_inters)
        if idx !== nothing
            bp = sys.general_inters[idx]
            # 2. Считаем текущий CV (ячейку)
            current_cv = Molly.calculate_cv(bp.cv_type, sys.coords, sys.atoms, sys.boundary, nothing)
            # 3. Насыпаем "песок" (обновляем общий словарь)
            logger.bias.data[current_cv] = get(logger.bias.data, current_cv, Int16(0)) + Int16(1)
            # Возвращаем количество уникальных посещенных ячеек для истории
            return length(logger.bias.data)
        end
    end
    return 0 # Если шаг не кратен интервалу
end


function metrosimula(sys, rotse, temperature)
    function rotmove!(sys; rots, mangle)
        function rotatebond!(sys::System, irotatoms::AbstractVector{Int},
            iaxis::Tuple{Int,Int}, angle::Unitful.Quantity)
            # промежуточные переменные: основание вектора вращения, 
            # нормализованый вектор вращения, 
            # коэфициенты для функции Родригеса

            zr = sys.coords[iaxis[1]]
            axis = normalize(sys.coords[iaxis[2]] - zr)
            cosa, sina = cos(angle), sin(angle)
            omc = 1 - cosa

            # только только для смещаемых атомов
            cv = view(sys.coords, irotatoms)

            # Внутренняя функция вращения (замыкание)
            # Принимает SVector{3, nm}, возвращает SVector{3, nm}
            function rodrigues_rotation(r)
                p = r - zr # Вектор относительно центра вращения
                # Родригеса формула
                p = p * cosa +
                    cross(axis, p) * sina +
                    axis * dot(axis, p) * omc
                return p + zr
            end

            cv .= rodrigues_rotation.(cv)

            return sys.coords
        end

        # rots = argse[:rots]
        # mangle = argse[:mangle]
        r = rand(rots)
        angle = (rand() - 0.5) * mangle
        rotatebond!(sys, r.irotatoms, r.axis, angle)

        return nothing

    end
    trialargs = Dict(
        :rots => rotse,
        :mangle => 1.0u"rad" # 0.2 Максимальный шаг
    )

    sim = MetropolisMonteCarlo(
        temperature=temperature,
        trial_moves=rotmove!,
        trial_args=trialargs,
    )

end

# function monsystemsetup(chargese, atypese, vdwe, coordse, torsionse; box_size=10.0u"nm")
function monsystemsetup(smilese; box_size=10.0u"nm", temperature=298.15u"K")
    aindexes, charges, atypes, vdw, coords, bonds, torsionic, bharmonics, aharmonics, rbonds = smilesmol(smilese)
    natoms = length(aindexes)

    # 1. Массы
    const_amasses = Dict(
        1 => 1.008, 6 => 12.011, 7 => 14.007, 8 => 15.999, 16 => 32.06
    )

    atoms = [
        Molly.Atom(
            index=i,
            charge=charges[i] * u"q",
            mass=const_amasses[Int(atypes[i])] * u"g/mol",
            σ=vdw[i][1] * u"nm",
            ϵ=vdw[i][2] * u"kJ/mol"
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
        coulomb_const=138.9354558u"kJ * nm * mol^-1 * q^-2"
    )

    # 5. Топология
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
    cvtorsions = NTuple{4,Int}[]
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
    to1 = Int[]
    to2 = Int[]
    to3 = Int[]
    to4 = Int[]
    torsions = PeriodicTorsion[]
    for t in torsionic
        push!(to1, t[:indices][1])
        push!(to2, t[:indices][2])
        push!(to3, t[:indices][3])
        push!(to4, t[:indices][4])
        # Создаем торсион. N=1, так как мы берем каждое слагаемое отдельно.
        # Molly ожидает NTuple, поэтому используем (val,)

        tp = PeriodicTorsion(
            periodicities=(Int(t[:period]),),
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
    bo1, bo2 = Int[], Int[]
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
    ao1, ao2, ao3 = Int[], Int[], Int[]
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

    cv_step = 0.1f0 # Шаг сетки в радианах
    hill_w = 1.5f0  # Высота холма в kJ/mol
    gridcv = GridTorsionsCV(cvtorsions, cv_step, :pbc) # optim?
    shared_memory = Dict{Vector{Int16},Int}()
    grid_bias = SparseGridBias(shared_memory, hill_w)

    metacpot = BiasPotential(gridcv, grid_bias)

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
        general_inters=(metacpot,),
        neighbor_finder=DistanceNeighborFinder(
            eligible=eligible,
            special=special,
            n_steps=10,
            dist_cutoff=1.2 * u"nm",
        ),
        loggers=(mc=MonteCarloLogger(),
            metac=MetadynamicsLogger(100, grid_bias),),
        energy_units=u"kJ/mol",
        force_units=u"kJ/mol/nm",
        k=8.314462618e-3u"kJ/mol/K"
    )

    return sys, metrosimula(sys, rots, temperature)
end


end
