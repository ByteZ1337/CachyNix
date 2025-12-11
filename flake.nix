{
  description = "CachyOS kernel flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    cachyos-kernel = {
      url = "github:CachyOS/linux-cachyos";
      flake = false;
    };

    cachyos-kernel-patches = {
      url = "github:CachyOS/kernel-patches";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, cachyos-kernel, cachyos-kernel-patches, ... }:
    let
      lib = nixpkgs.lib;
      pinnedPkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };
      overlay =
        final: prev:
        import ./kernels.nix {
          inherit lib;
          pkgs = pinnedPkgs;
          versions = builtins.fromJSON (builtins.readFile ./versions.json);
          cachyosKernelSrc = cachyos-kernel;
          cachyosPatchesSrc = cachyos-kernel-patches;
        };
    in
    {
      overlays.default = overlay;
      packages.x86_64-linux =
        let
          pkgs = import nixpkgs {
            system = "x86_64-linux";
            overlays = [ overlay ];
            config.allowUnfree = true;
          };
        in
        lib.filterAttrs (name: _: lib.hasPrefix "linux-cachyos-" name) pkgs;
    };
}
