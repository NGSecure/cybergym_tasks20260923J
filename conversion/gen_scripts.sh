#!/usr/bin/env bash
# Emit a converted bundle's two-phase run scripts:
#   build.sh  — phase 1, on the PUBLIC network (pulls n132/arvo:<id>-*), no creds
#   push.sh   — phase 2, on the SPECIAL/upload network, credentials from env
# Build and upload happen on different networks with a manual switch between, so
# they are separate scripts that share the same deterministic image tags.
#
# Usage: bash conversion/gen_scripts.sh <bundle-dir> [version-tag]
set -euo pipefail

BUNDLE="${1:?usage: gen_scripts.sh <bundle-dir> [version-tag]}"
VER="${2:-v0.0.1}"
BUNDLE="${BUNDLE%/}"
[ -d "$BUNDLE" ] || { echo "no such bundle dir: $BUNDLE" >&2; exit 1; }
ARVO_ID="$(basename "$BUNDLE" | sed -E 's/.*arvo-v2-([0-9]+)-.*/\1/')"
[[ "$ARVO_ID" =~ ^[0-9]+$ ]] || { echo "cannot parse arvo id from $BUNDLE" >&2; exit 1; }

cat > "$BUNDLE/build.sh" <<BUILD
#!/usr/bin/env bash
# Phase 1 — BUILD (run on the PUBLIC network; needs docker.io for n132/arvo).
# No platform credentials needed. When done, switch to the upload network and
# run push.sh. The two arvo images are baked in here, so push.sh only uploads.
#   bash $(basename "$BUNDLE")/build.sh
set -euo pipefail

HERE="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="\$(cd "\$HERE/.." && pwd)"
cd "\$WORKSPACE"
B="\$(basename "\$HERE")"

ARVO=$ARVO_ID
VER=$VER
MAIN_TAG="arvo_\${ARVO}_main:\${VER}"
TS_TAG="arvo_\${ARVO}_task_server:\${VER}"

echo "==> build main sandbox  \$MAIN_TAG"
docker build -t "\$MAIN_TAG" -f "\$B/environment/Dockerfile" "\$B/environment"
echo "==> build task-server   \$TS_TAG"
docker build -t "\$TS_TAG" "\$B/environment/task-server"

echo "==> self-check: task-server has vul+fix binaries baked in (non-blocking)"
docker run --rm --entrypoint sh "\$TS_TAG" -lc 'echo "VUL:"; ls /cybergym/vul/out 2>/dev/null | head; echo "FIX:"; ls /cybergym/fix/out 2>/dev/null | head; printf "ground_truth: "; [ -s /tests/ground_truth_poc ] && echo found || echo MISSING' || true

echo "==> built \$MAIN_TAG and \$TS_TAG"
echo "    now switch to the UPLOAD network and run:  bash \$B/push.sh"
BUILD
chmod +x "$BUNDLE/build.sh"

cat > "$BUNDLE/push.sh" <<PUSH
#!/usr/bin/env bash
# Phase 2 — PUSH + backfill (run on the SPECIAL/upload network, AFTER build.sh).
# These bundles live OUTSIDE the newplatform uv project, so point NEWPLATFORM_DIR
# at your local VulAgent/new_platform_harbor (the uv project that holds the
# newplatform package + its working env). Credentials come from the environment;
# everything else is pre-filled.
#   export CWM_PLATFORM_USERNAME='<账号>'
#   export CWM_PLATFORM_PASSWORD='<密码>'
#   export NEWPLATFORM_DIR=/path/to/VulAgent/new_platform_harbor
#   bash $(basename "$BUNDLE")/push.sh
set -euo pipefail

: "\${CWM_PLATFORM_USERNAME:?set CWM_PLATFORM_USERNAME}"
: "\${CWM_PLATFORM_PASSWORD:?set CWM_PLATFORM_PASSWORD}"
: "\${NEWPLATFORM_DIR:?set NEWPLATFORM_DIR to your local VulAgent/new_platform_harbor}"
[ -d "\$NEWPLATFORM_DIR" ] || { echo "NEWPLATFORM_DIR not a dir: \$NEWPLATFORM_DIR" >&2; exit 1; }

HERE="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"   # this bundle dir (absolute)
B="\$(basename "\$HERE")"

ARVO=$ARVO_ID
VER=$VER
PLATFORM_URL=http://7.244.3.60:8088
LINE=default
USER=platform
MAIN_TAG="arvo_\${ARVO}_main:\${VER}"
TS_TAG="arvo_\${ARVO}_task_server:\${VER}"

# build.sh must have run (on the public network) — the images are local.
for t in "\$MAIN_TAG" "\$TS_TAG"; do
  docker image inspect "\$t" >/dev/null 2>&1 || {
    echo "missing local image \$t — run 'bash \$HERE/build.sh' on the public network first" >&2
    exit 1
  }
done

echo "==> push both images to SWR (public/default) + backfill task.toml"
# Run the module from the newplatform uv project, but reference this bundle's
# files by absolute path so cwd doesn't matter.
cd "\$NEWPLATFORM_DIR"
uv run python -m newplatform push \\
  --platform-url "\$PLATFORM_URL" --line "\$LINE" --user "\$USER" \\
  --image docker_image="\$MAIN_TAG" \\
  --image task_server_image="\$TS_TAG" \\
  --refs "\$HERE/image_refs.json" \\
  --task-toml "\$HERE/task.toml" \\
  --yes
PUSH
chmod +x "$BUNDLE/push.sh"

echo "  wrote $BUNDLE/build.sh (public net) + $BUNDLE/push.sh (upload net)"
