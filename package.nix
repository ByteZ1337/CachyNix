{
  lib,
  buildLinux,
  stdenv,
  kernelPatchSet,
  fetchurl,
  cachyosKernelSrc,
  cachyosPatchesSrc,

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
  major = lib.versions.majorMinor version;
  modDirVersion = "${lib.versions.pad 3 version}${versionSuffix}";

  cachyosConfigFile = "${cachyosKernelSrc}/${variant}/config";
  cachyosPatches = "${cachyosPatchesSrc}/${major}/all/0001-cachyos-base-all.patch";

  marchFlags = lib.optionals (march != null) [
    "KCFLAGS=-march=${march}"
  ];

  patchedSrc = stdenv.mkDerivation {
    pname = "linux-cachyos-src";
    inherit version;

    src = fetchurl {
      url = "mirror://kernel/linux/kernel/v6.x/linux-${version}.tar.xz";
      hash = tarballHash;
    };

    patches = [
      kernelPatchSet.bridge_stp_helper.patch
      kernelPatchSet.request_key_helper.patch
      cachyosPatches
    ];

    postPatch = ''
      install -Dm644 ${cachyosConfigFile} arch/x86/configs/cachyos_defconfig
      sed -i -E 's/^EXTRAVERSION.*/EXTRAVERSION = ${versionSuffix}/' Makefile
    '';

    dontConfigure = true;
    dontBuild = true;
    dontFixup = true;

    installPhase = ''
      mkdir -p "$out"
      cp -r . "$out/"
    '';
  };

in
buildLinux {
  inherit version pname modDirVersion;
  src = patchedSrc;

  defconfig = "cachyos_defconfig";

  extraMakeFlags = marchFlags;

  ignoreConfigErrors = true;

  structuredExtraConfig = with lib.kernel; {
    NR_CPUS = lib.mkForce (freeform "512");

    LTO_NONE = lib.mkForce (if enableThinLTO then no else yes);
    LTO_CLANG_THIN = lib.mkForce (if enableThinLTO then yes else no);

    OVERLAY_FS = module;
    OVERLAY_FS_REDIRECT_DIR = no;
    OVERLAY_FS_REDIRECT_ALWAYS_FOLLOW = yes;
    OVERLAY_FS_INDEX = no;
    OVERLAY_FS_XINO_AUTO = no;
    OVERLAY_FS_METACOPY = no;
  } // lib.optionalAttrs isAmd {
    X86_AMD_PSTATE = yes;
    AMD_PMC = module;
  };

extraMeta = {
    description =
      "Linux CachyOS kernel (${pname})"
      + lib.optionalString (march != null) " tuned for ${march}"
      + lib.optionalString enableThinLTO " with thin lto";
    branch = lib.versions.majorMinor version;
    inherit march enableThinLTO isAmd;
  };
}
