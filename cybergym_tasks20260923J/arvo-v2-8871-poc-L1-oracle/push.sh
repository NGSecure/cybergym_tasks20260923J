#!/usr/bin/env bash
# Phase 2 — PUSH + backfill (run on the SPECIAL/upload network, AFTER build.sh).
# These bundles live OUTSIDE the newplatform uv project, so point NEWPLATFORM_DIR
# at your local VulAgent/new_platform_harbor (the uv project that holds the
# newplatform package + its working env). Credentials come from the environment;
# everything else is pre-filled.
#   export CWM_PLATFORM_USERNAME='<账号>'
#   export CWM_PLATFORM_PASSWORD='<密码>'
#   export NEWPLATFORM_DIR=/path/to/VulAgent/new_platform_harbor
#   bash arvo-v2-8871-poc-L1-oracle/push.sh
set -euo pipefail

: "${CWM_PLATFORM_USERNAME:?set CWM_PLATFORM_USERNAME}"
: "${CWM_PLATFORM_PASSWORD:?set CWM_PLATFORM_PASSWORD}"
: "${NEWPLATFORM_DIR:?set NEWPLATFORM_DIR to your local VulAgent/new_platform_harbor}"
[ -d "$NEWPLATFORM_DIR" ] || { echo "NEWPLATFORM_DIR not a dir: $NEWPLATFORM_DIR" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # this bundle dir (absolute)
B="$(basename "$HERE")"

ARVO=8871
VER=v0.0.1
PLATFORM_URL=http://7.244.3.60:8088
LINE=default
USER=platform
MAIN_TAG="arvo_${ARVO}_main:${VER}"
TS_TAG="arvo_${ARVO}_task_server:${VER}"

# build.sh must have run (on the public network) — the images are local.
for t in "$MAIN_TAG" "$TS_TAG"; do
  docker image inspect "$t" >/dev/null 2>&1 || {
    echo "missing local image $t — run 'bash $HERE/build.sh' on the public network first" >&2
    exit 1
  }
done

echo "==> push both images to SWR (public/default) + backfill task.toml"
# Run the module from the newplatform uv project, but reference this bundle's
# files by absolute path so cwd doesn't matter.
cd "$NEWPLATFORM_DIR"
uv run python -m newplatform push \
  --platform-url "$PLATFORM_URL" --line "$LINE" --user "$USER" \
  --image docker_image="$MAIN_TAG" \
  --image task_server_image="$TS_TAG" \
  --refs "$HERE/image_refs.json" \
  --task-toml "$HERE/task.toml" \
  --yes
