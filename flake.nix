{
  description = "Welcome to the development shell for the master's thesis project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {

      packages.${system}.default = {
       git = pkgs.git;
      };

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.git
          pkgs.nextflow
        ];
      };
    };
}
