{
  lib,
  buildLinux,
  kernelPatchSet,
  fetchurl,
  cachyosKernelSrc,

  version,
  tarballHash,
  variant,
  pname ? "linux-cachyos",
  march ? null,
  isAmd ? (march == "znver4"),
  versionSuffix ? "-cachyos",
  ...
}:

let
  modDirVersion = "${lib.versions.pad 3 version}${versionSuffix}";

  cachyosConfigFile = "${cachyosKernelSrc}/${variant}/config";

  makeFlags =
    lib.optionals (march != null) [
      "KCFLAGS=-march=${march}"
      "KCPPFLAGS=-march=${march}"
    ];

in
buildLinux {
  inherit version pname modDirVersion;

  src = fetchurl {
    url = "https://github.com/CachyOS/linux/releases/download/cachyos-${version}-1/cachyos-${version}-1.tar.gz";
    hash = tarballHash;
  };

  kernelPatches = [
    kernelPatchSet.bridge_stp_helper
    kernelPatchSet.request_key_helper
  ];
  
  defconfig = cachyosConfigFile;

  extraMakeFlags = [
    "EXTRAVERSION=${versionSuffix}"
  ]
  ++ makeFlags;

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
    // lib.optionalAttrs isAmd {
      X86_AMD_PSTATE = yes;
      AMD_PMC = module;
    };

  ignoreConfigErrors = true;

  extraMeta = {
    description =
      "Linux CachyOS kernel (${pname})"
      + lib.optionalString (march != null) " tuned for ${march}";
    branch = lib.versions.majorMinor version;
    inherit march isAmd;
  };
}
