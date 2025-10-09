# references:
# https://wiki.nixos.org/wiki/Flakes 

{
  description = "A flake file for the master's thesis project with cbmi and the ngs pipeline";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
   };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      # ref: https://discourse.nixos.org/t/allow-unfree-in-flakes/29904
      # need to add "config.allowUnfree = true" for sratoolkit
      pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
    in {
      # For global installation run: nix profile install .#git (with this flake.nix)
      # or use profile install nixpkgs#git
      packages.${system}.git = pkgs.git;

      devShells.${system}.default = pkgs.mkShell {
        # Add more tools here, only avaiable in devShell, make sure to choose a pkgs
        buildInputs = [ 
          pkgs.git 
          pkgs.nextflow 
          pkgs.singularity 
          pkgs.sratoolkit 
          pkgs.pigz
        ];
        shellHook = ''
          echo "Welcome to the development shell for the ngs pipeline project!"
   	    '';
      };
    };
}
