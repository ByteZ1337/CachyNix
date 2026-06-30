{
  lib,
  buildLinux,
  kernelPatchSet,
  fetchurl,
  cachyosKernelSrc,

  pkgsBuildHost,
  pkgsBuildBuild,
  overrideCC,
  patchelf,

  version,
  tarballHash,
  variant,
  pname ? "linux-cachyos",
  march ? null,
  isAmd ? (march == "znver4"),
  versionSuffix ? "-cachyos",
  lto ? "none",
  ...
}:

assert lib.assertOneOf "lto" lto [ "none" "thin" "full" ];

let
  kernelVersion = lib.elemAt (lib.splitString "-" version) 0;

  useLLVM = lto != "none";

  extraVersion = versionSuffix + lib.optionalString useLLVM "-lto";
  modDirVersion = "${lib.versions.pad 3 kernelVersion}${extraVersion}";

  cachyosConfigFile = "${cachyosKernelSrc}/${variant}/config";

  makeFlags =
    lib.optionals (march != null) [
      "KCFLAGS=-march=${march}"
      "KCPPFLAGS=-march=${march}"
    ];

  # nixpkgs' kernel builder wants the unwrapped LLVM tools passed explicitly
  noBintools = {
    bootBintools = null;
    bootBintoolsNoLibc = null;
  };
  hostLLVM = pkgsBuildHost.llvmPackages.override noBintools;
  buildLLVM = pkgsBuildBuild.llvmPackages.override noBintools;

  ltoMakeFlags = [
    "LLVM=1"
    "LLVM_IAS=1"
    "CC=${buildLLVM.clangUseLLVM}/bin/clang"
    "LD=${buildLLVM.lld}/bin/ld.lld"
    "HOSTLD=${hostLLVM.lld}/bin/ld.lld"
    "AR=${buildLLVM.llvm}/bin/llvm-ar"
    "HOSTAR=${hostLLVM.llvm}/bin/llvm-ar"
    "NM=${buildLLVM.llvm}/bin/llvm-nm"
    "STRIP=${buildLLVM.llvm}/bin/llvm-strip"
    "OBJCOPY=${buildLLVM.llvm}/bin/llvm-objcopy"
    "OBJDUMP=${buildLLVM.llvm}/bin/llvm-objdump"
    "READELF=${buildLLVM.llvm}/bin/llvm-readelf"
    "HOSTCC=${hostLLVM.clangUseLLVM}/bin/clang"
    "HOSTCXX=${hostLLVM.clangUseLLVM}/bin/clang++"
    # Mute nixpkgs CC wrapper warnings for Clang+LTO
    "NIX_CC_WRAPPER_SUPPRESS_TARGET_WARNING=1"
  ];

  llvmStdenv =
    let
      base = overrideCC hostLLVM.stdenv hostLLVM.clangUseLLVM;
    in
    base.override (_old: {
      extraNativeBuildInputs = [
        hostLLVM.lld
        patchelf
      ];
    });

  ltoConfig =
    with lib.kernel;
    {
      none = { };
      thin = {
        LTO_NONE = no;
        LTO_CLANG_THIN = yes;
        LTO_CLANG_FULL = no;
      };
      full = {
        LTO_NONE = no;
        LTO_CLANG_THIN = no;
        LTO_CLANG_FULL = yes;
      };
    }
    .${lto};

in
buildLinux (
  {
    inherit version pname modDirVersion;

    src = fetchurl {
      url = "https://github.com/CachyOS/linux/releases/download/cachyos-${version}/cachyos-${version}.tar.gz";
      hash = tarballHash;
    };

    kernelPatches = [
      kernelPatchSet.bridge_stp_helper
      kernelPatchSet.request_key_helper
    ];

    defconfig = cachyosConfigFile;

    extraMakeFlags = [
      "EXTRAVERSION=${extraVersion}"
    ]
    ++ makeFlags
    ++ lib.optionals useLLVM ltoMakeFlags;

    structuredExtraConfig =
      with lib.kernel;
      {
        NR_CPUS = lib.mkForce (freeform "512");

        OVERLAY_FS = module;
        OVERLAY_FS_REDIRECT_DIR = no;
        OVERLAY_FS_REDIRECT_ALWAYS_FOLLOW = yes;
        OVERLAY_FS_INDEX = no;
        OVERLAY_FS_XINO_AUTO = no;
        OVERLAY_FS_METACOPY = no;
      }
      // ltoConfig
      // lib.optionalAttrs isAmd {
        X86_AMD_PSTATE = yes;
        AMD_PMC = module;
      };

    ignoreConfigErrors = true;

    extraMeta = {
      description =
        "Linux CachyOS kernel (${pname})"
        + lib.optionalString (march != null) " tuned for ${march}"
        + lib.optionalString useLLVM " with Clang ${lto} LTO";
      branch = lib.versions.majorMinor version;
      inherit march isAmd lto;
    };
  }
  // lib.optionalAttrs useLLVM {
    stdenv = llvmStdenv;
  }
)
