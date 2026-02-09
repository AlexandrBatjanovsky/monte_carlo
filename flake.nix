{
  description = "Julia CUDA Monte Carlo Project with NixVim";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixvim.url = "github:nix-community/nixvim";
    flake-utils.url = "github:numtide/flake-utils";
    openff-flake.url = "path:/mnt/sda3/alexandersn/Work/moncarlo/openff-toolkit-dev";
  };

  outputs = { self, nixpkgs, nixvim, flake-utils, openff-flake, ... }:
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
          openff-flake.packages.${system}.openff-toolkit
          openff-flake.packages.${system}.openff-units
          openff-flake.packages.${system}.openff-utilities
          openff-flake.packages.${system}.openff-interchange
          openff-flake.packages.${system}.openff-forcefields
          # openff-flake.packages.${system}.openff-amber

          # debugpy    # Можно добавить для отладки
        ]);
        ambertools = openff-flake.packages.${system}.ambertools;

        # Определяем библиотеки CUDA
        # cuda-libs = with pkgs; [
        #   cudaPackages.cuda_nvcc
        #   cudaPackages.cudatoolkit
        #   linuxPackages.nvidia_x11
        #   libGL
        #   stdenv.cc.cc.lib
        # ];

        # Объединяем либы для LD_LIBRARY_PATH, чтобы не дублировать
        runtime-libs = with pkgs; [
          libGL
          libGLU
          freeglut
          libxkbcommon
          wayland
          xorg.libX11
          xorg.libXcursor
          xorg.libXrandr
          xorg.libXinerama
          xorg.libXi
          stdenv.cc.cc.lib
          # Добавляем CUDA в рантайм
          cudaPackages.cudatoolkit
          linuxPackages.nvidia_x11
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
            # pkgs.libGL
            # pkgs.libGLU
            # pkgs.freeglut
            # pkgs.libxkbcommon
            # pkgs.wayland
            # pkgs.xorg.libX11
            # pkgs.xorg.libXcursor
            # pkgs.xorg.libXrandr
            # pkgs.xorg.libXinerama
            # pkgs.xorg.libXi 

            openff-flake.packages.${system}.openff-toolkit
            openff-flake.packages.${system}.openff-units
            openff-flake.packages.${system}.openff-utilities
            openff-flake.packages.${system}.openff-interchange
            openff-flake.packages.${system}.openff-forcefields
            #openff-flake.packages.${system}.openff-amber
 
            ambertools
            pkgs.julia-bin
            pkgs.pkg-config
            python-env 
            myNixvim            
          ] ++ runtime-libs;

          shellHook = ''
            export JULIA_PYTHONCALL_EXE="${python-env}/bin/python3"
            export JULIA_PYTHONCALL_SKIP_LIB_CHECK=yes
            export JULIA_CONDAPKG_OFFLINE=yes
            export JULIA_CONDAPKG_BACKEND=Null              
            
            # Позволяет GLFW использовать системные либы
            export JULIA_GLFW_LIBRARY="" 

            # AmberTools

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
                      
            # export NIX_LD_LIBRARY_PATH="$SHARED_LIBS"
            export NIX_LD=$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)
            export LD_LIBRARY_PATH="$SHARED_LIBS:$LD_LIBRARY_PATH"
            # export LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
            
            # Магия для NVIDIA + Wayland + GLX
            export __GLX_VENDOR_LIBRARY_NAME=nvidia
            
            # alias vim="nvim"
            echo "⚡ Julia + CUDA + NixVim Flake Environment Ready (Wayland/NVIDIA fix applied)"
          '';
        };
      });
}
