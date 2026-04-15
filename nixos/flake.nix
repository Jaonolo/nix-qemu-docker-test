{
  description = "NixOS Docker runner VM (QEMU) - declarative config";

  inputs = {
    # Pin exact revisions so builds are reproducible without a flake.lock.
    nixpkgs.url = "github:NixOS/nixpkgs/7e495b747b51f95ae15e74377c5ce1fe69c1765f";
    nixos-generators.url = "github:nix-community/nixos-generators/8946737ff703382fda7623b9fab071d037e897d5";
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
        format = "qcow";
        modules = [ ./image.nix ];
      };

      # `nix build .#qcow2` will produce a bootable qcow2 image in `result/`.
    };
}

