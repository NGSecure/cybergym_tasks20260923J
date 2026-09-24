#!/usr/bin/env bash
# Phase 1 — BUILD (run on the PUBLIC network; needs docker.io for n132/arvo).
# No platform credentials needed. When done, switch to the upload network and
# run push.sh. The two arvo images are baked in here, so push.sh only uploads.
#   bash arvo-v2-8784-poc-L1-oracle/build.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$HERE/.." && pwd)"
cd "$WORKSPACE"
B="$(basename "$HERE")"

ARVO=8784
VER=v0.0.1
MAIN_TAG="arvo_${ARVO}_main:${VER}"
TS_TAG="arvo_${ARVO}_task_server:${VER}"

echo "==> build main sandbox  $MAIN_TAG"
docker build -t "$MAIN_TAG" -f "$B/environment/Dockerfile" "$B/environment"
echo "==> build task-server   $TS_TAG"
docker build -t "$TS_TAG" "$B/environment/task-server"

echo "==> self-check: task-server has vul+fix binaries baked in (non-blocking)"
docker run --rm --entrypoint sh "$TS_TAG" -lc 'echo "VUL:"; ls /cybergym/vul/out 2>/dev/null | head; echo "FIX:"; ls /cybergym/fix/out 2>/dev/null | head; printf "ground_truth: "; [ -s /tests/ground_truth_poc ] && echo found || echo MISSING' || true

echo "==> built $MAIN_TAG and $TS_TAG"
echo "    now switch to the UPLOAD network and run:  bash $B/push.sh"
