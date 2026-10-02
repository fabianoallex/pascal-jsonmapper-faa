#!/bin/sh
# Builds the samples on Linux FPC inside a Docker container, with heaptrc,
# runs them and compares each one's whole output with its expected.txt.
# Acceptance: every sample exits with 0, prints exactly expected.txt and
# reports 0 unfreed blocks. No database or network: the samples' output is
# deterministic, so a full diff is checked instead of a few grepped lines.
#
# The repository is mounted read-only and copied inside the container.
#
# FPC_IMAGE: any image with FPC 3.2.2 on the PATH (default: fpc322-bookworm).
# Note: heaptrc on Linux only writes its summary when given a log file
# (HEAPTRC=log=...), hence the logs below.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${FPC_IMAGE:-fpc322-bookworm}"
MOUNT="$ROOT"
command -v cygpath >/dev/null 2>&1 && MOUNT="$(cygpath -w "$ROOT")"

MSYS_NO_PATHCONV=1 docker run --rm -v "$MOUNT:/src:ro" "$IMAGE" sh -c '
  set -e
  mkdir -p /t && cp -r /src/src /src/samples /t/
  FAILED=0
  check() { # folder program
    mkdir -p /t/u-$2
    cd /t/samples/$1
    fpc -v0 -Mdelphi -Fu/t/src -Fi/t/src -FU/t/u-$2 -gh -gl -o/t/$2 $2.dpr > /t/build-$2.log 2>&1 \
      || { grep -iE "error|fatal" /t/build-$2.log | head -30; FAILED=1; return; }
    cd /t
    rm -f /t/heap-$2.txt
    HEAPTRC="log=/t/heap-$2.txt" ./$2 > /t/out-$2.txt 2>&1 && CODE=0 || CODE=$?
    if [ "$CODE" != 0 ]; then echo "$2: exit code $CODE"; cat /t/out-$2.txt; FAILED=1; return; fi
    if ! diff -u /t/samples/$1/expected.txt /t/out-$2.txt; then echo "$2: output differs from expected.txt"; FAILED=1; return; fi
    if ! grep -qE "^0 unfreed memory blocks" /t/heap-$2.txt; then echo "$2: leaks"; head -60 /t/heap-$2.txt; FAILED=1; return; fi
    echo "$2: ok (output matches expected.txt, 0 unfreed blocks)"
  }
  check 01-basics Basics
  check 02-custom-converter CustomConverter
  exit $FAILED'
