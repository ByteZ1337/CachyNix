{ lib, pkgs, versions, cachyosKernelSrc, cachyosPatchesSrc }:
let
  mkKernel = 
    { pname, stream, march, enableThinLTO, variant}:
    pkgs.callPackage ./package.nix {
      version = versions.${stream}.version;
      tarballHash = versions.${stream}.tarballHash;
      kernelPatchSet = pkgs.kernelPatches;
      llvmPackages = pkgs.llvmPackages_21;
      inherit pname march enableThinLTO variant cachyosKernelSrc cachyosPatchesSrc;
    };

  streams = [ "latest" "lts" ];

  variants = [
    { suffix = ""; march = null; lto = false; }
    { suffix = "-lto"; march = null; lto = true; }
    { suffix = "-x86-64-v3"; march = "x86-64-v3"; lto = false; }
    { suffix = "-x86-64-v3-lto"; march = "x86-64-v3"; lto = true; }
    { suffix = "-x86-64-v4"; march = "x86-64-v4"; lto = false; }
    { suffix = "-x86-64-v4-lto"; march = "x86-64-v4"; lto = true; }
    { suffix = "-znver4"; march = "znver4"; lto = false; }
    { suffix = "-znver4-lto"; march = "znver4"; lto = true; }
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
            enableThinLTO = variant.lto;
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