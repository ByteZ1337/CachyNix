{
  lib,
  buildLinux,
  kernelPatchSet,
  fetchurl,
  cachyosKernelSrc,
  cachyosPatchesSrc,
  llvmPackages ? null,

  version,
  tarballHash,
  variant,
  pname ? "linux-cachyos",
  march ? null,
  enableThinLTO ? true,
  isAmd ? (march == "znver4"),
  versionSuffix ? "-cachyos",
  ...
}:

let
  major = lib.versions.major version;
  majorMinor = lib.versions.majorMinor version;
  modDirVersion = "${lib.versions.pad 3 version}${versionSuffix}";

  cachyosConfigFile = "${cachyosKernelSrc}/${variant}/config";
  cachyosPatches = "${cachyosPatchesSrc}/${majorMinor}/all/0001-cachyos-base-all.patch";

  makeFlakgs =
    lib.optionals (march != null) [
      "KCFLAGS=-march=${march}"
      "KCPPFLAGS=-march=${march}"
    ]
    ++ lib.optionals enableThinLTO [
      "LLVM=1"
      "LLVM_IAS=1"
    ];

in
buildLinux {
  inherit version pname modDirVersion;

  src = fetchurl {
    url = "mirror://kernel/linux/kernel/v${major}.x/linux-${version}.tar.xz";
    hash = tarballHash;
  };

  kernelPatches = [
    kernelPatchSet.bridge_stp_helper
    kernelPatchSet.request_key_helper
    {
      name = "cachyos-base-patch";
      patch = cachyosPatches;
    }
  ];

  defconfig = cachyosConfigFile;

  extraNativeBuildInputs = lib.optionals enableThinLTO builtins.attrValues {
    inherit (llvmPackages)
      clang
      lld
      llvm
      ;
  };

  extraMakeFlags = [
    "KERNELRELEASE=${modDirVersion}"
  ]
  ++ makeFlakgs;

  structuredExtraConfig =
    with lib.kernel;
    {
      NR_CPUS = lib.mkForce (freeform "512");

      LTO_NONE = lib.mkForce (if enableThinLTO then no else yes);
      LTO_CLANG_THIN = lib.mkForce (if enableThinLTO then yes else no);

      OVERLAY_FS = module;
      OVERLAY_FS_REDIRECT_DIR = no;
      OVERLAY_FS_REDIRECT_ALWAYS_FOLLOW = yes;
      OVERLAY_FS_INDEX = no;
      OVERLAY_FS_XINO_AUTO = no;
      OVERLAY_FS_METACOPY = no;
    }
    // lib.optionalAttrs isAmd {
      X86_AMD_PSTATE = yes;
      AMD_PMC = module;
    };

  ignoreConfigErrors = true;

  extraMeta = {
    description =
      "Linux CachyOS kernel (${pname})"
      + lib.optionalString (march != null) " tuned for ${march}"
      + lib.optionalString enableThinLTO " with thin lto";
    branch = lib.versions.majorMinor version;
    inherit march enableThinLTO isAmd;
  };
}
