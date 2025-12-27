FROM nixos/nix:latest

RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
RUN nix profile add "github:ByteZ1337/attic/feat/upload-in-parts#attic-client"
RUN nix profile add "nixpkgs#nix-output-monitor"

WORKDIR /build

COPY <<'EOF' /bin/build-and-push.sh
#!/bin/sh
set -e
git config --global --add safe.directory /build
attic login "$ATTIC_USER" "$ATTIC_ENDPOINT" "$ATTIC_TOKEN"
attic use "$ATTIC_CACHE_NAME"
OUT_PATHS=$(nix build -L ".#${TARGET}^*" --no-link --print-out-paths --log-format internal-json -v 2> >(nom --json))
echo "$OUT_PATHS" | xargs attic push "$ATTIC_CACHE_NAME"
EOF

RUN chmod +x /bin/build-and-push.sh

COPY . /build

CMD ["/bin/build-and-push.sh"]