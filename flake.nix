{
  description = "keimoger's NixOS configuration";

  inputs = {
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=nixos-unstable";
    plover-flake.url = "git+https://github.com/dnaq/plover-flake";
    lanzaboote = {
      url = "github:nix-community/lanzaboote/master"; # or latest stable tag/master
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, plover-flake, lanzaboote, ... }@inputs: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux"; # Or your system architecture
      specialArgs = { inherit inputs; };
      modules = [
        lanzaboote.nixosModules.lanzaboote
        ./configuration.nix
      ];
    };
  };
}
