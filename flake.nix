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

      # Add python env for TaxonomicClassification debugging
      torchnlp = pkgs.python312Packages.buildPythonPackage rec {
        pname = "pytorch-nlp";
        version = "0.5.0";
        format = "setuptools";
        src = pkgs.fetchPypi {
          inherit pname version;
          sha256 = "sha256-q6euy8bwlS7d6LwGc5TI1Dt0o1xZSdYQZmbQGmTZz6s=";
        };
        nativeBuildInputs = with pkgs.python312Packages; [ setuptools ];
        propagatedBuildInputs = with pkgs.python312Packages; [ torch ];
        doCheck = false;
      };

      pythonEnv = pkgs.python312.withPackages (ps: with ps; [
        numpy
        pandas
        seaborn
        scikit-learn
        biopython
        transformers
        torch
        torchvision
        torchaudio
        torchnlp
        tables
      ]);
    in {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.git
          pkgs.nextflow
          # pkgs.nf-test
          pkgs.singularity
          pkgs.pigz
          pythonEnv     # development for Taxonomic NGS NN
        ];

        shellHook = ''
          echo "Welcome to the development shell for the ngs pipeline project!"
        '';
      };
    };
}
