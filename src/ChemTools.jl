module ChemTools


export smilesmol

using PythonCall
using StaticArrays

function smilesmol(molenter)

    Molecule = pyimport("openff.toolkit").Molecule
    ForceField = pyimport("openff.toolkit").ForceField
    Topology = pyimport("openff.toolkit").Topology
    Interchange = pyimport("openff.interchange").Interchange
    # getopenmmenergy = pyimport("openff.interchange.drivers").get_openmm_energies
    unit = pyimport("openff.units").unit

    if ispath(molenter)
        mol = Molecule.from_file(molenter)
    else
        mol = Molecule.from_smiles(molenter)
    end

    mol = mol.canonical_order_atoms()
    # print(mol, mol.bonds)
    mol.generate_conformers(n_conformers=1)
    # println(mol.conformers[0].m_as(unit.nanometers))
    topology = Topology.from_molecules(mol)
    ff = ForceField("openff-2.1.0.offxml")
    mol.assign_partial_charges(partial_charge_method="am1bcc")
    interchange = ff.create_interchange(topology)
    # println(getopenmmenergy(interchange).total_energy.m_as(unit.kilojoule / unit.mol))
    minfunc = pyimport("openff.interchange.operations.minimize.openmm").minimize_openmm
    newcoords = minfunc(interchange, tolerance=10.0 * unit.kilojoule / (unit.nanometer * unit.mole), max_iterations=0)
    # println(getopenmmenergy(interchange).total_energy.m_as(unit.kilojoule / unit.mol))
    interchange.positions = newcoords
    # println(getopenmmenergy(interchange).total_energy.m_as(unit.kilojoule / unit.mol))
    # dcoords = pyconvert(Vector{SVector{3,Float32}}, mol.conformers[0].m_as(unit.nanometers))

    dcoords = pyconvert(Vector{SVector{3,Float32}}, newcoords.m_as(unit.nanometers))
    # println(dcoords)

    daindexes = pyconvert(Vector{Int}, pyeval("""
       [
          mol.atom_index(_)+1
          for _ in mol.atoms
       ]
       """, pydict(mol=mol,)))

    datypes = pyconvert(Dict{Int,Float32}, pyeval("""
       {
          mol.atom_index(_)+1:_.atomic_number 
          for _ in mol.atoms
       }
      """, pydict(mol=mol,)))

    dbonds = pyconvert(Vector{Tuple{Int,Int}}, pyeval("""
     [
        (b.atom1_index + 1, b.atom2_index + 1)
        for b in mol.bonds
     ]	    	    	    	    	       
     """, pydict(mol=mol,)))

    dcharges = pyconvert(Dict{Int,Float64}, pyeval("""
      {
          topk.atom_indices[0] + 1: charge.m_as("elementary_charge")
          for topk, charge in vdw.charges.items()
      }
      """, pydict(vdw=interchange.collections["Electrostatics"],)))
    dvdw = pyconvert(Dict{Int,Tuple{Float64,Float64}}, pyeval("""
     {
         topk.atom_indices[0] + 1: (
             vdw.potentials[potk].parameters["sigma"].m_as("nanometer"),
             vdw.potentials[potk].parameters["epsilon"].m_as("kilojoule/mole")
         )
         for topk, potk in vdw.key_map.items()
     }
     """, pydict(vdw=interchange.collections["vdW"],)))

    dtorsions = pyconvert(Vector{Dict{Symbol,Union{Int,Float32,Tuple{Int,Int,Int,Int}}}},
        pyeval("""
        [
            {
                'indices': [i + 1 for i in topk.atom_indices],
                'period': tors.potentials[potk].parameters['periodicity'].m,
                'phase': tors.potentials[potk].parameters['phase'].m_as('radian'),
                'k': tors.potentials[potk].parameters['k'].m_as('kilojoule/mole')
            }
            for topk, potk in tors.key_map.items()
        ]
        """, pydict(tors=interchange.collections["ProperTorsions"])))

    dbharmonics = pyconvert(Vector{Vector{Union{Vector{Int},Float32}}}, pyeval("""
       [
           [
              list(tk.atom_indices), 
              coll.potentials[pk].parameters['k'].m_as('kilojoule / (mole * nanometer**2)'),
              coll.potentials[pk].parameters['length'].m_as('nanometer')
           ] 
           for tk, pk in coll.key_map.items()
       ]
       """,
        pydict(coll=interchange.collections["Bonds"])))

    daharmonics = pyconvert(Vector{Vector{Any}}, pyeval("""
       [
           [
               list(tk.atom_indices), 
               coll.potentials[pk].parameters['k'].m_as('kilojoule / (mole * radian**2)'),
               coll.potentials[pk].parameters['angle'].m_as('radian')
           ] 
           for tk, pk in coll.key_map.items()
       ]
       """, pydict(coll=interchange.collections["Angles"],)))



    rbonds = pyconvert(Vector{Tuple{Int,Int}}, pyeval("""
                      [(bond.atom1_index+1, bond.atom2_index+1) for bond in rotbonds]
                  """,
        pydict(rotbonds=mol.find_rotatable_bonds(),)))

    return daindexes, dcharges, datypes, dvdw, dcoords,
    dbonds, dtorsions, dbharmonics, daharmonics,
    rbonds
end

# # Функция для конвертации масс из RDKit в Unitful
# function getmollyatoms(py_mol)
#     atoms = []
#     for i in 0:py_mol.GetNumAtoms()-1
#         m = pyconvert(Float64, py_mol.GetAtomWithIdx(i).GetMass())
#         # Присваиваем массу в атомных единицах (u)
#         push!(atoms, Atom(index=Int64(i + 1), mass=m * u"u", charge=0.0))
#     end
#     return atoms
# end
# 
# # function gettorsions(py_mol)
# #
# # end
# 
# function smilestomolly(smiles)
#     # 1. Создаем молекулу и добавляем водороды
#     py_mol = rdkit.MolFromSmiles(smiles)
#     py_mol = rdkit.AddHs(py_mol)
# 
#     # 2. Генерируем 3D координаты (Embed)
#     allchem.EmbedMolecule(py_mol, allchem.ETKDG())
#     allchem.MMFFOptimizeMolecule(py_mol) # Немного расслабим структуру
# 
#     # 3. Вытаскиваем координаты в Julia
#     conf = py_mol.GetConformer()
#     num_atoms = py_mol.GetNumAtoms()
# 
#     coords = [
#         SVector(
#             pyconvert(Float64, conf.GetAtomPosition(i).x) / 10.0, # Перевод в нм
#             pyconvert(Float64, conf.GetAtomPosition(i).y) / 10.0,
#             pyconvert(Float64, conf.GetAtomPosition(i).z) / 10.0
#         )u"nm" for i in 0:num_atoms-1
#     ]
#     return getmollyatoms(py_mol), coords
# end
# 

end
