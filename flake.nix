# references:
# https://wiki.nixos.org/wiki/Flakes 
# https://discourse.nixos.org/t/allow-unfree-in-flakes/29904
# nixos-vscode-server support (failed): https://github.com/nix-community/nixos-vscode-server

{
  description = "A flake file for the master's thesis project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    #vscode-server.url = "github:nix-community/nixos-vscode-server";
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
        # Add more tools here, only avaiable in devShell
        buildInputs = [ pkgs.git pkgs.nextflow pkgs.singularity pkgs.sratoolkit ];
        shellHook = ''
          echo "Welcome to the development shell!"
   	'';
      };
     # nixosConfigurations.pumpkin03 = nixpkgs.lib.nixosSystem {
     #   modules = [
     #     vscode-server.nixosModules.default
     #     ({ config, pkgs, ... }: {
     #       services.vscode-server.enable = true;
     #     })
     #   ];
     # };
    };
}
