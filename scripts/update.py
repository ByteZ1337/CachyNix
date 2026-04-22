#!/usr/bin/env python3
import io
import json
import os
import subprocess
import tarfile
from pathlib import Path

import requests
import zstandard as zstd

CACHYOS_DB_URL = "https://mirror.cachyos.org/repo/x86_64_v3/cachyos-v3/cachyos-v3.db"
ROOT = Path(__file__).resolve().parent.parent
VERSIONS_PATH = ROOT / "versions.json"

STREAMS = {
    "latest": "linux-cachyos",
    "lts": "linux-cachyos-lts",
}

def fetch_cachyos_db() -> tarfile.TarFile:
    resp = requests.get(CACHYOS_DB_URL, timeout=60)
    resp.raise_for_status()
    decompressed = zstd.ZstdDecompressor().stream_reader(io.BytesIO(resp.content)).read()
    return tarfile.open(fileobj=io.BytesIO(decompressed), mode="r:")

def get_cachyos_version(tar: tarfile.TarFile, pkg_name: str, gh_token: str) -> str:
    for member in tar.getmembers():
        if member.name.startswith(f"{pkg_name}-") and member.name.endswith("/desc"):
            desc = tar.extractfile(member).read().decode()
            lines = desc.splitlines()
            idx = lines.index("%VERSION%")
            full = lines[idx + 1].strip()
            if ":" in full:
                full = full.split(":", 1)[1]
            # cachy's package repo and github releases sometimes have out of sync pkgrels, so fall back to github to see what the actual latest pkgrel we can get is
            version = full.rsplit("-", 1)[0]
            full = f"{version}-1"
            if gh_token:
                url = f"https://api.github.com/repos/cachyos/linux/releases?per_page=100"
                headers = {"Authorization": f"Bearer {gh_token}"}
                resp = requests.get(url, headers=headers, timeout=60)
                resp.raise_for_status()
                data = resp.json()
                for entry in data:
                    tag = entry["tag_name"]
                    if tag.startswith(f"cachyos-{version}-"):
                        full = tag[len("cachyos-"):]
                        break
            return full
    raise RuntimeError(f"{pkg_name} not found in db")

def version_tuple(v: str) -> tuple[int, ...]:
    pkgrel = 1
    if "-" in v:
        v, pkgrel_str = v.rsplit("-", 1)
        try:
            pkgrel = int(pkgrel_str)
        except ValueError: # TODO - rc handling
            pass
    return tuple(int(x) for x in v.split(".")) + (pkgrel,)

def nix_prefetch_sri(version: str) -> str:
    url = f"https://github.com/CachyOS/linux/releases/download/cachyos-{version}/cachyos-{version}.tar.gz"
    raw = subprocess.check_output(["nix-prefetch-url", url], text=True).strip()
    return subprocess.check_output(["nix", "hash", "convert", "--hash-algo", "sha256", raw], text=True).strip()

def main():
    # flake updates
    print(f"updating cachyos flake inputs")
    subprocess.run(["nix", "flake", "update"], cwd=ROOT, check=True)

    # versions.json updates
    versions = json.loads(VERSIONS_PATH.read_text())
    original = json.dumps(versions, sort_keys=True)

    tar = fetch_cachyos_db()

    for stream, pkg_name in STREAMS.items():
        cachyos_ver = get_cachyos_version(tar, pkg_name, os.getenv("GITHUB_TOKEN"))
        current_ver = versions.get(stream, {}).get("version")

        print(f"{stream}: cachyos={cachyos_ver} current={current_ver}")

        if current_ver and version_tuple(cachyos_ver) <= version_tuple(current_ver):
            print(f"  up-to-date")
            continue

        print(f"  updating to {cachyos_ver}")
        sri = nix_prefetch_sri(cachyos_ver)

        versions.setdefault(stream, {})
        versions[stream]["version"] = cachyos_ver
        versions[stream]["tarballHash"] = sri

    if json.dumps(versions, sort_keys=True) != original:
        VERSIONS_PATH.write_text(json.dumps(versions, indent=2) + "\n")
        print("versions.json updated")

if __name__ == "__main__":
    main()
