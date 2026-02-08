{
  description = "OpenFF Toolkit Development Environment";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    openff-units-src = { url = "github:openforcefield/openff-units"; flake = false; };
    openff-utilities-src = { url = "github:openforcefield/openff-utilities"; flake = false; };
    openff-forcefields-src = { url = "github:openforcefield/openff-forcefields"; flake = false; };
    openff-amber-src = { url = "github:openforcefield/openff-amber-ff-ports"; flake = false; };
    openff-interchange-src = { url = "github:openforcefield/openff-interchange"; flake = false; };    
  };
  outputs = { self, nixpkgs, flake-utils, ... } @ inputs:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        python = pkgs.python3;
        ambertools = pkgs.stdenv.mkDerivation rec {
          pname = "ambertools";
          version = "25";
          
          # Указываем на папку, которую ты распаковал
          src = ./vendor/ambertools25_u.tar.bz2;

          nativeBuildInputs = with pkgs; [
            cmake gfortran flex bison patch which pkg-config perl python3
          ];

          buildInputs = with pkgs; [
            libyaml bzip2 zlib libxml2 netcdf fftw readline
            xorg.libX11 xorg.libXext xorg.libXv xorg.libXmu 
            xorg.libXt xorg.libICE xorg.libSM
            boost183 
            netcdf
            netcdffortran            
            # netcdff
            arpack

            blas
            lapack                        
          ];

          # Магия Amber: они хотят билд ВНЕ папки исходников
          # Nix делает это в отдельной директории билда по умолчанию,
          # но нам нужно явно указать префикс установки ($out)
          cmakeFlags = [
            "-DCOMPILER=GNU"
            "-DINSTALL_TESTS=OFF"
            "-DDOWNLOAD_MINICONDA=OFF"
            "-DBUILD_GUI=OFF"
            "-DBUILD_PYTHON=OFF"
            "-DCHECK_UPDATES=OFF"
            "-DUPDATE_AMBER=OFF"
            "-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
            #"-DCMAKE_INSTALL_PREFIX=$out"
            # ЗАСТАВЛЯЕМ ИСПОЛЬЗОВАТЬ СИСТЕМНЫЕ ЛИБЫ
            "-DFORCE_EXTERNAL_LIBS=boost;netcdf;arpack"
            # МАГИЧЕСКИЙ ФЛАГ: заставляет их доверять Nix-у
            "-DTRUST_SYSTEM_LIBS=TRUE"
            
            # "-DCMAKE_CXX_STANDARD=14"
            # "-DBUILD_QUICK=OFF"
            "-DCMAKE_CXX_STANDARD=14"
            "-DCMAKE_CXX_STANDARD_REQUIRED=ON"
            "-DCMAKE_CXX_EXTENSIONS=OFF"

            # "-DBUILD_MOFT=OFF"            
            "-DUSE_SYSTEM_BOOST=ON"
            "-DUSE_SYSTEM_NETCDF=ON"
          ];
          # enableParallelBuilding = false;

          # Перед конфигурированием нам нужно зайти в корень, 
          # где лежит CMakeLists.txt (в Amber25 это может быть сразу в src)
          preConfigure = ''
            export AMBERHOME=$(pwd)
            # ФИКС ДЛЯ GCC 15: Добавляем недостающий заголовок в cpptraj
            # Ищем файл helpme_standalone.h и вставляем #include <cstdint> после первого появления #include
            sed -i '1i#include <cstdint>' AmberTools/src/cpptraj/src/helpme_standalone.h
            # Помогаем найти библиотеки
            export NETCDF_HOME=${pkgs.netcdf}
            export NETCDF_FORTRAN_HOME=${pkgs.netcdffortran}
            patchShebangs .
          '';

          # После установки Amber создаст файл amber.sh, 
          # но нам нужно убедиться, что бинарники в $out/bin доступны
          postInstall = ''
            # Если инсталлер положил всё в $out/ambertools25, перенесем в корень $out
            if [ -d "$out/amber25" ]; then
              mv $out/amber25/* $out/
            fi
          '';
          postFixup = ''
            # Удаляем битую ссылку, чтобы Nix не ругался. 
            # В 99% случаев ff12pol не критичен для работы openff-toolkit.
            rm -f $out/dat/leap/cmd/leaprc.protein.ff12pol
          '';
        };

        mkOpenFFPkg = name: src: deps: python.pkgs.buildPythonPackage rec {
          pname = name;
          version = "0.2.0"; 
          inherit src;
          
          format = "pyproject"; 
          doCheck = false;
          
          dontCheckRuntimeDeps = true;

          SETUPTOOLS_SCM_PRETEND_VERSION = version;
          VERSIONINGIT_PRETEND_VERSION = version;

          patchPhase = ''
            if [ -f pyproject.toml ]; then
              sed -i 's/dynamic = \["version"\]/version = "${version}"/' pyproject.toml
              sed -i '/versioningit/d' pyproject.toml
            fi
          '';

          nativeBuildInputs = with python.pkgs; [ 
            setuptools 
            pypaBuildHook
            pypaInstallHook
            setuptools-scm 
          ];

          propagatedBuildInputs = with python.pkgs; [ 
            numpy 
            packaging 
            pint 
          ] ++ deps;
        };

        openff-toolkit-dev = python.pkgs.buildPythonPackage rec {
          pname = "openff-toolkit";
          version = "0.2.0"; 
          src = ./.; 
          format = "pyproject";
          doCheck = false;
          dontCheckRuntimeDeps = true;

          SETUPTOOLS_SCM_PRETEND_VERSION = version;
          VERSIONINGIT_PRETEND_VERSION = version;

          patchPhase = ''
            if [ -f pyproject.toml ]; then
              # Просто заменяем слово versioningit на setuptools везде. 
              # Это не сломает структуру кавычек и запятых.
              sed -i 's/versioningit/setuptools/g' pyproject.toml
              # И прописываем версию
              sed -i 's/dynamic = \["version"\]/version = "${version}"/' pyproject.toml
            fi
          '';

          nativeBuildInputs = with python.pkgs; [ 
            setuptools versioningit pypaBuildHook pypaInstallHook setuptools-scm 
          ];
          
          propagatedBuildInputs = with python.pkgs; [ 
            openff-units openff-utilities openff-forcefields openff-amber
            openff-interchange numpy rdkit ase networkx packaging pint pydantic ambertools
            cachetools xmltodict typing-extensions python-constraint openmm
          ];
        };

        openff-utilities    = mkOpenFFPkg "openff-utilities"     inputs.openff-utilities-src   [ ];
        openff-units        = mkOpenFFPkg "openff-units"         inputs.openff-units-src       [ openff-utilities ];
        openff-forcefields  = mkOpenFFPkg "openff-forcefields"   inputs.openff-forcefields-src [ ];
        openff-amber        = mkOpenFFPkg "openff-amber"         inputs.openff-amber-src       [ ];
        openff-interchange  = mkOpenFFPkg "openff-interchange"   inputs.openff-interchange-src [ openff-utilities 
                                                                                                 openff-units ];

      in
      {
        packages = {
          ambertools = ambertools;
          openff-toolkit-dev = openff-toolkit-dev;
          openff-interchange = openff-interchange;
          openff-units = openff-units;
          openff-utilities = openff-utilities;
          openff-forcefields = openff-forcefields; 
          openff-amber = openff-amber;
          
          default = openff-toolkit-dev;
          # sdefault = ambertools;
        };

        # devShells.default = pkgs.mkShell {
        #   buildInputs = [ ambertools-pkg ];
        # };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            ambertools
            (python.withPackages (ps: [
              ps.numpy
              ps.rdkit
              ps.packaging
              ps.networkx
              ps.xmltodict
              ps.bson
              ps.python-constraint
              ps.cachetools
              ps.typing-extensions
              ps.openmm
              ps.pydantic
              ps.ase
              
              # для nglview
              ps.nglview
              ps.ipywidgets
              ps.jupyter

              openff-units
              openff-utilities
              openff-forcefields
              openff-amber
              openff-interchange              
              openff-toolkit-dev
              
              ps.pip
              ps.setuptools
            ]))
          ];

          shellHook = ''
            export AMBERHOME=${ambertools}
            export PATH=$AMBERHOME/bin:$PATH

            if [[ -z "$ZSH_VERSION" ]]; then
              export SHELL=${pkgs.zsh}/bin/zsh
              exec ${pkgs.zsh}/bin/zsh
            fi

            export PYTHONPATH=$PWD:$PYTHONPATH

            echo "OpenFF Toolkit dev environment (with units & utilities) loaded!"
          '';
        };
      });
}

