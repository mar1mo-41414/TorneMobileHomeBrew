#!/bin/bash
# Build the bundled libmpv stack for the Linux desktop package
# (plan 82) and produce the release archive
# build/libmpv-linux-v0.38.0-arib1.tar.gz.
#
# The whole build runs in a Debian 12 container (the Dockerfile
# in this directory), so the resulting libraries run on Debian 12
# and later — and on Ubuntu 22.04+, whose glibc is the floor the
# build checks for. The container is --rm and writes only into
# build/libmpv-linux-build/, which ends up root-owned; removing
# that scratch dir afterwards may need a throwaway container or
# sudo for the same reason.
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT="$(cd ../.. && pwd)"
TAG="libmpv-linux-v0.38.0-arib1"
WORK="$REPO_ROOT/build/libmpv-linux-build"
mkdir -p "$WORK"
cp Dockerfile build-inside.sh "$WORK/"
docker build -t tmhb-libmpv-builder:deb12 -f Dockerfile .
docker run --rm -v "$WORK:/work" tmhb-libmpv-builder:deb12 bash /work/build-inside.sh
(cd "$WORK/bundle" && tar czf "$REPO_ROOT/build/$TAG.tar.gz" ./*)
echo "built: build/$TAG.tar.gz"
sha256sum "$REPO_ROOT/build/$TAG.tar.gz"
