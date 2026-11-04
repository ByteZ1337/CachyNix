const db_url = "https://mirror.cachyos.org/repo/x86_64_v4/cachyos-znver4/cachyos-znver4.db"
const streams = { latest: "linux-cachyos", lts: "linux-cachyos-lts" }
# sanity supply-chain cooldown. Bypass with --skip-cooldown
const cooldown = 3day

def tarball-url [version: string] {
  $"https://github.com/CachyOS/linux/releases/download/cachyos-($version)/cachyos-($version).tar.gz"
}

def tarball-hash [version: string] {
  let hash = http get --raw (tarball-url $version) | hash sha256 --binary | encode base64
  $"sha256-($hash)"
}

def repo-version [db: path, pkg: string] {
  let desc = ^tar --zstd -xOf $db --wildcards $"($pkg)-[0-9]*/desc" | lines
  let full = $desc | get (($desc | enumerate | where item == "%VERSION%" | first | get index) + 1)
  $full | str replace --regex '^\d+:' '' | str replace --regex '-[^-]+$' ''
}

def newer [candidate: string, current: string] {
  $candidate != $current and ([$current $candidate] | sort --natural | last) == $candidate
}

# github releases newer than what we ship, but not past the repo's pkgver
def candidates [releases: list, pkgver: string, current: string] {
  $releases
    | where tag_name =~ '^cachyos-\d+\.\d+\.\d+-\d+$'
    | each {|r|
        let version = $r.tag_name | str replace "cachyos-" ""
        { version: $version, pkgver: ($version | str replace --regex '-\d+$' ''), published: ($r.published_at | into datetime) }
      }
    | where { not (newer $in.pkgver $pkgver) and ($current == null or (newer $in.version $current)) }
    | sort-by --natural version
}

def main [--skip-cooldown] {
  cd $env.FILE_PWD

  let db = mktemp --tmpdir cachyos-XXXXXX.db
  http get --raw $db_url | save --force $db

  let releases = gh api "repos/cachyos/linux/releases?per_page=100" | from json

  let original = open versions.json
  let versions = $streams | transpose stream pkg | reduce --fold $original {|it, versions|
    let pkgver = repo-version $db $it.pkg
    let current = $versions | get --optional $it.stream
    let found = candidates $releases $pkgver $current.version?

    print $"($it.stream): repo=($pkgver) newest=($found | last | get --optional version | default 'none') current=($current.version? | default 'none')"

    # catch silently replaced release assets for the version we already ship
    if $current != null {
      let hash = tarball-hash $current.version
      if $hash != $current.tarballHash {
        error make { msg: $"($it.stream): tarball for ($current.version) changed upstream: expected ($current.tarballHash), got ($hash)" }
      }
    }

    if ($found | is-empty) {
      print "  up-to-date"
      return $versions
    }
    # take the newest release that has cleared the cooldown
    let release = $found | where { $skip_cooldown or ((date now) - $in.published) >= $cooldown } | last
    for held in ($found | where { $release == null or (newer $in.version $release.version) }) {
      print $"  holding ($held.version) published (((date now) - $held.published) | format duration hr) ago until it is ($cooldown) old"
    }
    if $release == null { return $versions }

    print $"  updating to ($release.version)"
    $versions | upsert $it.stream { version: $release.version, tarballHash: (tarball-hash $release.version) }
  }

  rm $db

  if $versions != $original {
    $versions | to json --indent 2 | $in + "\n" | save --force versions.json
    print "versions.json updated"
  }
}
