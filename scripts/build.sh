#!/bin/sh
TARGET=${1:-linux-cachyos-latest-x86-64-v3}
docker build --file ./scripts/Dockerfile -t cachyos-builder .
docker run --rm -it --privileged --env-file .env -e TARGET="$TARGET" cachyos-builder