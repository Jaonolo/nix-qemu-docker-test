{
  description = "NixOS Docker runner VM (QEMU) - declarative config";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nixos-generators }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      nixosConfigurations.nix-docker-vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ({ ... }: {
            imports = [ ./configuration.nix ];
          })
        ];
      };

      packages.${system}.qcow2 = nixos-generators.nixosGenerate {
        inherit system;
        format = "qcow2";
        modules = [ ./image.nix ];
      };

      # `nix build .#qcow2` will produce a bootable qcow2 image in `result/`.
    };
}

