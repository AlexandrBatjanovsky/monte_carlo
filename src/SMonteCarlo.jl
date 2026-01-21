module SMonteCarlo


#export  

using ..Molly
using ..CUDA
using ..Unitful
using LinearAlgebra
using StaticArrays
include("ChemTools.jl")

"""
    rotatebond!(sys, atoms_to_rotate, axis_indices, angle)

    Вращает группу атомов `atoms_to_rotate` вокруг оси, заданной индексами двух атомов `axis_indices` 
    (например, связь C-O). Использует формулу поворота Родрига для сохранения внутренней геометрии.

    # Аргументы
    # - `sys`: объект `Molly.System`.
    # - `atoms_to_rotate::Vector{Int}`: индексы атомов, которые будут перемещены.
    # - `axis_indices::Tuple{Int, Int}`: пара индексов (центр, направление), задающая ось связи.
    # - `angle::Quantity`: угол поворота (обязательно с единицами измерения, например `0.1u"rad"`).
    #
    # # Пример
    # ```julia
    # rotatebond!(sys, [3, 4, 5], (1, 2), 0.5u"rad")
"""
function rotatebond!(sys::System, irotatoms::AbstractVector{Int}, iaxis::Tuple{Int,Int}, angle::Unitful.Quantity)
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

function setupsystem()
    mol = smilestomolly("C=CCO")
end

end

