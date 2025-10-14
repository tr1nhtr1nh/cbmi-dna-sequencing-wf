# references:
# https://wiki.nixos.org/wiki/Flakes 
# https://www.youtube.com/watch?v=JCeYq72Sko0&t=803s
# Alternative: create env with conda

{
  description = "A flake file for the master's thesis project with cbmi and the ngs pipeline";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
   };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
    in {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.git
          pkgs.nextflow 
          pkgs.singularity 
          pkgs.pigz
        ];

        shellHook = ''
          echo "Welcome to the development shell for the ngs pipeline project!"
        '';
      };
    };
}
