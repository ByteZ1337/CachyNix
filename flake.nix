{
  description = "CachyOS kernel flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    cachyos-kernel = {
      url = "github:CachyOS/linux-cachyos";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, cachyos-kernel, ... }:
    let
      lib = nixpkgs.lib;
      pinnedPkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };
      linuxPackagesFor =
        kernel:
        let
          packages = pinnedPkgs.linuxPackagesFor kernel;
          isLLVM = builtins.elem "LLVM=1" packages.kernel.commonMakeFlags;
        in
        if !isLLVM then
          packages
        else
          packages.extend (
            _final: prev:
            lib.mapAttrs (
              name: value:
              # lto kernels have their compiler recorded as "clang ..., LLD ...", but
              # `clang --version` never names the linker, so nvidia's CC check fails.
              if name == "kernelModuleMakeFlags" then
                value ++ [ "IGNORE_CC_MISMATCH=1" ]
              else if name != "kernel" && lib.isDerivation value && value ? overrideAttrs then
                value.overrideAttrs (old: {
                  postPatch = (old.postPatch or "") + ''
                    if [ -f Makefile ]; then
                      substituteInPlace Makefile --replace-quiet gcc cc
                    fi
                  '';
                })
              else
                value
            ) prev
          );

      overlay =
        final: prev:
        import ./kernels.nix {
          inherit lib linuxPackagesFor;
          pkgs = pinnedPkgs;
          versions = builtins.fromJSON (builtins.readFile ./versions.json);
          cachyosKernelSrc = cachyos-kernel;
        };
    in
    {
      overlays.default = overlay;
      lib.x86_64-linux = { inherit linuxPackagesFor; };
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
