{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell rec {
        buildInputs = with pkgs; [
          clang
          lld
          python3
          scons
          pkg-config

          xorg.libXcursor
          xorg.libXinerama
          xorg.libXi
          xorg.libXrandr
          wayland-utils
          wayland-scanner
          mesa
          libGLU
          libGL
          alsa-lib
          pulseaudio

        ];
        LD_LIBRARY_PATH = nixpkgs.lib.makeLibraryPath (
          with pkgs;
          [
            fontconfig
            fontconfig.dev
            fontconfig.lib
            wayland
            wayland.dev
            libxkbcommon
            libxkbcommon.dev
            libdecor
            libdecor.dev
            vulkan-loader
            vulkan-loader.dev
            alsa-lib
            alsa-lib.dev
            libpulseaudio
            libpulseaudio.dev
          ]
        );
      };
      formatter.${system} = pkgs.nixfmt-tree;
    };
}
