{
  description = "Julia CUDA Monte Carlo Project with NixVim";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixvim.url = "github:nix-community/nixvim";
    flake-utils.url = "github:numtide/flake-utils";
    amber-flake.url = "git+file:../openff-toolkit";
  };

  outputs = { self, nixpkgs, nixvim, flake-utils, amber-flake, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            cudaSupport = true;
          };
        };

        python-env = pkgs.python3.withPackages (ps: with ps; [
          # для openff-toolkit

          rdkit 
          numpy
          pip
          setuptools
          # ВОТ ОНИ:
          amber-flake.packages.${system}.openff-toolkit-dev
          amber-flake.packages.${system}.openff-units
          #amber-flake.packages.${system}.openff-utilities
          #amber-flake.packages.${system}.openff-interchange
          #amber-flake.packages.${system}.openff-forcefields
          #amber-flake.packages.${system}.openff-amber

          setuptools
          wheel
          # debugpy    # Можно добавить для отладки
        ]);
        ambertools = amber-flake.packages.${system}.ambertools;

        # Определяем библиотеки CUDA
        cuda-libs = with pkgs; [
          cudaPackages.cuda_nvcc
          cudaPackages.cudatoolkit
          linuxPackages.nvidia_x11
          libGL
          stdenv.cc.cc.lib
        ];

        # Конфигурируем Neovim специально под этот проект
        myNixvim = import ./nixvim.nix {
          inherit pkgs system nixvim;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          # Пакеты, доступные в shell
          buildInputs = [
            # для makie
            pkgs.libGL
            pkgs.libGLU
            pkgs.freeglut
            pkgs.libxkbcommon
            pkgs.wayland
            pkgs.xorg.libX11
            pkgs.xorg.libXcursor
            pkgs.xorg.libXrandr
            pkgs.xorg.libXinerama
            pkgs.xorg.libXi 


            amber-flake.packages.${system}.openff-toolkit-dev
            amber-flake.packages.${system}.openff-units
            #amber-flake.packages.${system}.openff-utilities
            #amber-flake.packages.${system}.openff-interchange
            #amber-flake.packages.${system}.openff-forcefields
            #amber-flake.packages.${system}.openff-amber
 
            
            ambertools
            pkgs.julia-bin
            pkgs.pkg-config
            python-env 
            myNixvim            

            myNixvim # Наш редактор теперь часть окружения!
          ] ++ cuda-libs;

          shellHook = ''
            export JULIA_PYTHONCALL_EXE="${python-env}/bin/python3"
            export JULIA_PYTHONCALL_SKIP_LIB_CHECK=yes
            export JULIA_CONDAPKG_OFFLINE=yes
            export JULIA_CONDAPKG_BACKEND=Null              
            
            # Позволяет GLFW использовать системные либы
            export JULIA_GLFW_LIBRARY="" 
            
            export AMBERHOME="${ambertools}"

            # NVIDIA + OpenGL пути
            export CUDA_WERROR=0

            # Формируем чистый путь к либам
            SHARED_LIBS="${pkgs.lib.makeLibraryPath (with pkgs; [
              libGL
              libGLU
              libxkbcommon
              wayland
              xorg.libX11
              stdenv.cc.cc.lib
            ])}:/run/opengl-driver/lib"
            
            export GDK_SCALE=2
                      
            export NIX_LD_LIBRARY_PATH="$SHARED_LIBS"
            export NIX_LD=$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)
            export LD_LIBRARY_PATH="$SHARED_LIBS:$LD_LIBRARY_PATH"

            # Магия для NVIDIA + Wayland + GLX
            export __GLX_VENDOR_LIBRARY_NAME=nvidia
            
            alias vim="nvim"
            echo "⚡ Julia + CUDA + NixVim Flake Environment Ready (Wayland/NVIDIA fix applied)"
          '';
        };
      });
}
