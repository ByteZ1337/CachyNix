{ lib, pkgs, linuxPackagesFor, versions, cachyosKernelSrc }:
let
  mkKernel =
    { pname, stream, march, variant, lto }:
    pkgs.callPackage ./package.nix {
      version = versions.${stream}.version;
      tarballHash = versions.${stream}.tarballHash;
      kernelPatchSet = pkgs.kernelPatches;
      inherit pname march variant lto cachyosKernelSrc;
    };

  streams = [ "latest" "lts" ];

  archVariants = [
    { suffix = ""; march = null; }
    { suffix = "-x86-64-v3"; march = "x86-64-v3"; }
    { suffix = "-x86-64-v4"; march = "x86-64-v4"; }
    { suffix = "-znver4"; march = "znver4"; }
  ];

  ltoVariants = [
    { suffix = ""; lto = "none"; }
    { suffix = "-lto"; lto = "thin"; }
  ];

  kernels = lib.listToAttrs(
    lib.concatMap(stream:
      lib.concatMap(arch:
        lib.map(lto:
          let
            name = "linux-cachyos-${stream}${arch.suffix}${lto.suffix}";
          in
          {
            inherit name;
            value = mkKernel {
              inherit stream;
              pname = name;
              march = arch.march;
              lto = lto.lto;
              variant = if stream == "lts" then "linux-cachyos-lts" else "linux-cachyos";
            };
          }
        ) ltoVariants
      ) archVariants
    ) streams
  );

  packages = lib.mapAttrs'(name: kernel: {
    name = "linuxPackages_cachyos_${lib.replaceStrings [ "linux-cachyos-" "-" ] [ "" "_" ] name}";
    value = linuxPackagesFor kernel;
  }) kernels;

in kernels // packages
