{ lib, pkgs, versions, cachyosKernelSrc, cachyosPatchesSrc }:
let
  mkKernel = 
    { pname, stream, march, variant}:
    pkgs.callPackage ./package.nix {
      version = versions.${stream}.version;
      tarballHash = versions.${stream}.tarballHash;
      kernelPatchSet = pkgs.kernelPatches;
      inherit pname march variant cachyosKernelSrc cachyosPatchesSrc;
    };

  streams = [ "latest" "lts" ];

  variants = [
    { suffix = ""; march = null; }
    { suffix = "-x86-64-v3"; march = "x86-64-v3"; }
    { suffix = "-x86-64-v4"; march = "x86-64-v4"; }
    { suffix = "-znver4"; march = "znver4"; }
  ];

  kernels = lib.listToAttrs(
    lib.concatMap(stream:
      lib.map(variant:
        let
          name = "linux-cachyos-${stream}${variant.suffix}";
        in
        {
          inherit name;
          value = mkKernel {
            inherit stream;
            pname = name;
            march = variant.march;
            variant = if stream == "lts" then "linux-cachyos-lts" else "linux-cachyos";
          };
        }
      ) variants
    ) streams
  );

  packages = lib.mapAttrs'(name: kernel: {
    name = "linuxPackages_cachyos_${lib.replaceStrings [ "linux-cachyos-" "-" ] [ "" "_" ] name}";
    value = pkgs.linuxPackagesFor kernel;
  }) kernels;

in kernels // packages