{ pkgs ? import <nixpkgs> { 
    config = { 
      allowUnfree = true; 
      cudaSupport = true; 
    }; 
  } 
}:

let
  # Список необходимых библиотек
  cuda-libs = with pkgs; [
    cudaPackages.cuda_nvcc
    cudaPackages.cudatoolkit
    linuxPackages.nvidia_x11
    libGL
    stdenv.cc.cc.lib
  ];
in
pkgs.mkShell {
  buildInputs = with pkgs; [
    julia-bin
  ] ++ cuda-libs;

  shellHook = ''
    # Для nix-ld
    export NIX_LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath cuda-libs}:/run/opengl-driver/lib"
    export NIX_LD=$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)

    # Важно для Julia: иногда она ищет libcuda.so напрямую в LD_LIBRARY_PATH
    export LD_LIBRARY_PATH="/run/opengl-driver/lib:${pkgs.lib.makeLibraryPath cuda-libs}:$LD_LIBRARY_PATH"
    
    echo "Julia + CUDA environment ready"
  '';
}
