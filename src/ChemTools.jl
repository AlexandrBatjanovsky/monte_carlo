module ChemTools


export smilestomolly

using PythonCall
using StaticArrays
using ..Molly
using ..Unitful

rdkit = pyimport("rdkit.Chem")
allchem = pyimport("rdkit.Chem.AllChem")

# Функция для конвертации масс из RDKit в Unitful
function getmollyatoms(py_mol)
    atoms = []
    for i in 0:py_mol.GetNumAtoms()-1
        m = pyconvert(Float64, py_mol.GetAtomWithIdx(i).GetMass())
        # Присваиваем массу в атомных единицах (u)
        push!(atoms, Atom(index=Int64(i + 1), mass=m * u"u", charge=0.0))
    end
    return atoms
end

# function gettorsions(py_mol)
#
# end

function smilestomolly(smiles)
    # 1. Создаем молекулу и добавляем водороды
    py_mol = rdkit.MolFromSmiles(smiles)
    py_mol = rdkit.AddHs(py_mol)

    # 2. Генерируем 3D координаты (Embed)
    allchem.EmbedMolecule(py_mol, allchem.ETKDG())
    allchem.MMFFOptimizeMolecule(py_mol) # Немного расслабим структуру

    # 3. Вытаскиваем координаты в Julia
    conf = py_mol.GetConformer()
    num_atoms = py_mol.GetNumAtoms()

    coords = [
        SVector(
            pyconvert(Float64, conf.GetAtomPosition(i).x) / 10.0, # Перевод в нм
            pyconvert(Float64, conf.GetAtomPosition(i).y) / 10.0,
            pyconvert(Float64, conf.GetAtomPosition(i).z) / 10.0
        )u"nm" for i in 0:num_atoms-1
    ]
    return getmollyatoms(py_mol), coords
end


end
