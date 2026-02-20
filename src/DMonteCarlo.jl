module DMonteCarlo


using Molly
# using CUDA
using Unitful
using StaticArrays
using LinearAlgebra

export GridTorsionsCV, AbstractGridBias, AsyncSparseGridBias, SinglSparseGridBias, MetadynamicsLogger, rotmove!

# cv по двугранным углам
struct GridTorsionsCV{T}
    indices::Vector{NTuple{4,Int16}}
    grid_step::Float32
    correction::Symbol
end
function Molly.calculate_cv(cv::GridTorsionsCV{T}, coords, atoms, boundary, velocities; kwargs...) where {T}
    # Создаем временный кортеж или используем ntuple для скорости
    return ntuple(T) do i
        idx = cv.indices[i]
        ang = torsion_angle(coords[idx[1]], coords[idx[2]], coords[idx[3]], coords[idx[4]], boundary)
        return round(Int16, (ang + pi) / cv.grid_step)
    end
end

abstract type AbstractGridBias end
# память, биас
struct SinglSparseGridBias{T} <: AbstractGridBias
    data::Dict{NTuple{T,Int16},Float32}     # память системы
    W0::Float32                             # Начальная высота холма (kJ/mol)
    temp::Float32                           # Температура системы (в Кельвинах)
    gamma::Float32                          # Bias Factor (например, 10.0)
end
struct AsyncSparseGridBias{T} <: AbstractGridBias
    data::Dict{NTuple{T,Int16},Float32}
    delta::Dict{NTuple{T,Int16},Float32}    # разница между начальной памятью 
    # и конечной (для паралельной работы)
    W0::Float32                             # Начальная высота холма (kJ/mol)
    temp::Float32                           # Температура системы (в Кельвинах)
    gamma::Float32                          # Bias Factor (например, 10.0)
end
function Molly.potential_energy(bias::AbstractGridBias, cv; kwargs...)
    return get(bias.data, cv, 0.0f0) * u"kJ/mol"
end
function recordhill!(bias::SinglSparseGridBias, key)
    # Извлекаем параметры
    kb = 0.00831446f0 # kJ/(mol*K)
    dT = bias.temp * (bias.gamma - 1.0f0)
    # Считаем текущий накопленный потенциал V(s)
    cV = get(bias.data, key, 0.0f0)
    # Вычисляем высоту нового холма
    Wstep = bias.W0 * exp(-cV / (kb * dT))
    # Кладём "слой песка" новой толщины
    bias.data[key] = cV + Wstep
    # bias.delta[ccv] = cV + Wstep
end
function recordhill!(bias::AsyncSparseGridBias, key)
    # Извлекаем параметры
    kb = 0.00831446f0 # kJ/(mol*K)
    dT = bias.temp * (bias.gamma - 1.0f0)
    # 3. Считаем текущий накопленный потенциал V(s)
    cV = get(bias.data, key, 0.0f0)
    # 4. Вычисляем высоту нового холма
    Wstep = bias.W0 * exp(-cV / (kb * dT))
    # 5. Кладём "слой песка" новой толщины
    bias.data[key] = cV + Wstep
    bias.delta[key] = get(bias.delta, key, 0.0f0) + Wstep
end


# "логер" заполняющий память системы  
struct MetadynamicsLogger
    cv_type::GridTorsionsCV
    interval::Int
    bias::AbstractGridBias
end
function Molly.log_property!(logger::MetadynamicsLogger, sys, buffers, neighbors, step_n, args...; kwargs...)
    if step_n % logger.interval == 0
        # idx = findfirst(i -> i isa BiasPotential && i.cv_type isa GridTorsionsCV, sys.general_inters)
        # if idx !== nothing
        #     bp = sys.general_inters[idx]
        #     bias = bp.bias_type # Наша SparseGridBias
        #     # 1. Определяем текущую ячейку на сетке
        #     ccv = Molly.calculate_cv(bp.cv_type, sys.coords, sys.atoms, sys.boundary, nothing)
        #     recordhill!(bias, ccv)
        #     return length(bias.data)
        # end
        # Используем bias, который уже лежит в логгере (ты его там определил!)
        # Но нам нужны CV_type, чтобы посчитать координаты. 
        # Если CV_type тоже сохранить в логгер, будет еще быстрее:
        ccv = Molly.calculate_cv(logger.cv_type, sys.coords, sys.atoms, sys.boundary, nothing)
        recordhill!(logger.bias, ccv)
        return length(logger.bias.data)
    end
    # return nothing  # проверить поведение логера!
end

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
    r = rand(rots)
    angle = (rand() - 0.5) * mangle
    rotatebond!(sys, r.irotatoms, r.axis, angle)
    return nothing
end


end
