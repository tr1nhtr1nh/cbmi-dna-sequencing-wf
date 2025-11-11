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

      torchnlp = pkgs.python312Packages.buildPythonPackage rec {
        pname = "pytorch-nlp";
        version = "0.5.0";
        format = "setuptools";
        src = pkgs.fetchPypi {
          inherit pname version;
          # <-- dein "got:"-Hash aus der Fehlermeldung
          sha256 = "sha256-q6euy8bwlS7d6LwGc5TI1Dt0o1xZSdYQZmbQGmTZz6s=";
        };
        nativeBuildInputs = with pkgs.python312Packages; [ setuptools ];
        propagatedBuildInputs = with pkgs.python312Packages; [ pytorch ];
        doCheck = false;
      };

      pythonEnv = pkgs.python312.withPackages (ps: with ps; [
        numpy
        pandas
        seaborn
        scikitlearn
        biopython
        transformers
        pytorch
        torchvision
        torchaudio
        torchnlp
      ]);
    in {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.git
          pkgs.nextflow
          pkgs.singularity
          pkgs.pigz
          pkgs.docker
          pythonEnv
        ];
      };
    };
}

