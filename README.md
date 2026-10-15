# CachyNix

CachyOS kernels for NixOS.

## Usage

Add the flake as an input:

```nix
inputs.cachynix.url = "github:bytez1337/cachynix";
```

then add the overlay and pick a kernel:

```nix
nixpkgs.overlays = [ inputs.cachynix.overlays.default ];
boot.kernelPackages = pkgs.linuxPackages_cachyos_lts;
```

Kernels are named `linux-cachyos-<stream><march><lto>` and the matching package sets
`linuxPackages_cachyos_<stream><march><lto>` (`-` -> `_`):

| | Options |
|---|---|
| stream | `latest`, `lts` |
| march | none, `-x86-64-v3`, `-x86-64-v4`, `-znver4` |
| lto | none, `-lto` (Clang ThinLTO) |

So for example `linuxPackages_cachyos_lts`, `linuxPackages_cachyos_latest_x86_64_v3` or
`linuxPackages_cachyos_latest_znver4_lto`.

## Binary cache

Only `linux-cachyos-latest-znver4-lto` gets built by CI, since that's the one I'm running. Everything else will build
locally.

```nix
nix.settings = {
  substituters = [ "https://cache.creepy.sh/cachyos" ];
  trusted-public-keys = [ "cachyos:cm+GC47yVJ6nd6tIQDx0qlCfWnxyJv3fL/rWr7FDSSg=" ];
};
```

Don't set `inputs.nixpkgs.follows` on this flake if you want cache hits. Out-of-tree modules like nvidia aren't cached, those will still build against the kernel on your machine.
