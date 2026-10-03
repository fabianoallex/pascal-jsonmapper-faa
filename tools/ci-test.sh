#!/bin/sh
# Everything CI runs (.github/workflows/ci.yml), also runnable locally with
# Docker: the FPCUnit mirrors are checked against their DUnitX masters, the
# unit suite runs with heaptrc, and the samples are built, run and diffed
# against their expected.txt. All on Linux FPC 3.2.2.
# Delphi Community Edition can't build headless, so the Delphi side is still
# validated in the IDE (see README.md, "Tests").
#
# FPC image: built here from Debian bookworm's fpc package (3.2.2) and tagged
# jsonmapper-fpc322, unless FPC_IMAGE names an existing one.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -z "${FPC_IMAGE:-}" ]; then
  FPC_IMAGE=jsonmapper-fpc322
  docker build -q -t "$FPC_IMAGE" - <<'DOCKERFILE' >/dev/null
FROM debian:bookworm
RUN apt-get update && apt-get install -y --no-install-recommends fpc && rm -rf /var/lib/apt/lists/*
DOCKERFILE
fi
export FPC_IMAGE

echo "== unit suite"
sh tools/test_fpc_docker.sh
echo "== samples"
sh tools/test_samples_docker.sh
