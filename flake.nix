{
  description = "CachyOS kernel flake";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.zst";

    cachyos-kernel = {
      url = "github:CachyOS/linux-cachyos";
      flake = false;
    };
  };

  outputs =
    { nixpkgs, cachyos-kernel, ... }:
    let
      lib = nixpkgs.lib;

      # Temp until pahole 1.33: CachyOS allows Rust with LTO + BTF which needs unreleased pahole
      paholeOverlay = final: prev: {
        pahole =
          if prev.pahole.version == "1.32" then
            prev.pahole.overrideAttrs {
              version = "1.32-unstable-2026-11-14";
              src = final.fetchzip {
                url = "https://git.kernel.org/pub/scm/devel/pahole/pahole.git/snapshot/pahole-72b61b0ce99995733d36f704acb53a64044ee85e.tar.gz";
                hash = "sha256-kmOF2tg7EfC1nZYxgBU4XROYXaB2KQwNJVBz6nGL4Yk=";
              };
            }
          else
            lib.warn "nixpkgs has pahole ${prev.pahole.version}, remove paholeOverlay from flake.nix" prev.pahole;
      };

      pinnedPkgs = import nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
        overlays = [ paholeOverlay ];
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
