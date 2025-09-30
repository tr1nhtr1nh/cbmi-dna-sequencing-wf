{
  description = "A flake file for the master's thesis project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      # For global installation run: nix profile install .#git
      # or nix profile install nixpkgs#git
      packages.${system}.git = pkgs.git;
      devShells.${system}.default = pkgs.mkShell {
        # Add more tools here, only avaiable in devShell
        buildInputs = [ pkgs.git pkgs.nextflow pkgs.singularity ];
	shellHook = ''
	  echo "Welcome to the devShell!"
	'';
      };
    };
}
