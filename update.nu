const db_url = "https://mirror.cachyos.org/repo/x86_64_v4/cachyos-znver4/cachyos-znver4.db"
const streams = { latest: "linux-cachyos", lts: "linux-cachyos-lts" }

def tarball-url [version: string] {
  $"https://github.com/CachyOS/linux/releases/download/cachyos-($version)/cachyos-($version).tar.gz"
}

def repo-version [db: path, pkg: string] {
  let desc = ^tar --zstd -xOf $db --wildcards $"($pkg)-[0-9]*/desc" | lines
  let full = $desc | get (($desc | enumerate | where item == "%VERSION%" | first | get index) + 1)
  $full | str replace --regex '^\d+:' '' | str replace --regex '-[^-]+$' ''
}

# cachy's package repo and github releases sometimes have out of sync pkgrels, so fall back to github to see what the actual latest pkgrel we can get is
def release-version [pkgver: string] {
  let token = $env.GITHUB_TOKEN? | default ""
  if $token == "" { return $"($pkgver)-1" }
  
  http get --headers [Authorization $"Bearer ($token)"] "https://api.github.com/repos/cachyos/linux/releases?per_page=100"
    | get tag_name
    | where ($it | str starts-with $"cachyos-($pkgver)-")
    | get 0?
    | default $"cachyos-($pkgver)-1"
    | str replace "cachyos-" ""
}

def newer [candidate: string, current: string] {
  $candidate != $current and ([$current $candidate] | sort --natural | last) == $candidate
}

def main [] {
  cd $env.FILE_PWD

  let db = mktemp --tmpdir cachyos-XXXXXX.db
  http get --raw $db_url | save --force $db

  let original = open versions.json
  let versions = $streams | transpose stream pkg | reduce --fold $original {|it, versions|
    let available = release-version (repo-version $db $it.pkg)
    let current = $versions | get --optional $it.stream | get --optional version

    print $"($it.stream): cachyos=($available) current=($current)"

    if $current != null and not (newer $available $current) {
      print "  up-to-date"
      return $versions
    }

    print $"  updating to ($available)"
    let hash = http get --raw (tarball-url $available) | hash sha256 --binary | encode base64
    $versions | upsert $it.stream { version: $available, tarballHash: $"sha256-($hash)" }
  }

  rm $db

  if $versions != $original {
    $versions | to json --indent 2 | $in + "\n" | save --force versions.json
    print "versions.json updated"
  }
}
