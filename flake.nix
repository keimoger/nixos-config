{
  description = "keimoger's NixOS configuration";

  inputs = {
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=nixos-unstable";
    plover-flake.url = "git+https://github.com/dnaq/plover-flake";
    plover-russian-firebird = {
      url = "path:/home/keimoger/projects/plover-russian-firebird";
      flake = false;
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote/master"; # or latest stable tag/master
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = { self, nixpkgs, plover-flake, lanzaboote, home-manager, ... }@inputs: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux"; # Or your system architecture
      specialArgs = { inherit inputs; };
      modules = [
        lanzaboote.nixosModules.lanzaboote
        home-manager.nixosModules.home-manager
        ./configuration.nix
      ];
    };
  };
}
