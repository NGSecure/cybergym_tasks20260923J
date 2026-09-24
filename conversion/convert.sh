#!/usr/bin/env bash
# Convert one ARVO "prime" oracle bundle into the new-platform (CyberGym) format,
# and emit that bundle's two-phase run scripts: build.sh (public net, local
# build) + push.sh (upload net, push both images + backfill).
#
# Usage:  bash conversion/convert.sh <bundle-dir> [version-tag]
#   <bundle-dir>   e.g. arvo-v2-289-poc-L1-oracle
#   [version-tag]  image tag suffix, default v0.0.1
#
# What it does (see SKILL.md for the why):
#   1. environment/task-server/       Dockerfile (FROM n132/arvo:<id>-{vul,fix},
#                                      bakes vul+fix binaries) + generic task_server.py
#   2. environment/docker-compose.yaml rewritten to a `task-server` service
#                                      (port 9111, AUTH_TOKEN, /health healthcheck)
#   3. environment/submit.sh           -> task-server:9111 /submit (multipart)
#   4. tests/test.sh + tests/verify.py -> /verify with X-Submission-Token
#   5. environment/oracle/             removed (dead once compose no longer uses it)
#   6. <bundle>/build.sh + push.sh     generated (public-net build / upload-net
#                                      push); params pre-filled, creds from env
#
# The AUTH_TOKEN reused is the bundle's own ORACLE_TOKEN, so it already matches
# across task-server env and the verifier. solution/solve.sh is left as-is (it
# writes a known-good PoC to /workspace/poc, which the new test.sh picks up).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$HERE/templates"

BUNDLE="${1:?usage: convert.sh <bundle-dir> [version-tag]}"
VER="${2:-v0.0.1}"
BUNDLE="${BUNDLE%/}"

[ -d "$BUNDLE" ] || { echo "no such bundle dir: $BUNDLE" >&2; exit 1; }
[ -d "$BUNDLE/environment/oracle" ] || { echo "skip $BUNDLE: no environment/oracle (not a prime bundle, or already converted)" >&2; exit 2; }
[ -d "$BUNDLE/environment/task-server" ] && { echo "skip $BUNDLE: environment/task-server already exists (already converted)" >&2; exit 3; }

# --- per-bundle values ------------------------------------------------------
ARVO_ID="$(basename "$BUNDLE" | sed -E 's/.*arvo-v2-([0-9]+)-.*/\1/')"
[ -n "$ARVO_ID" ] && [[ "$ARVO_ID" =~ ^[0-9]+$ ]] || { echo "cannot parse arvo id from $BUNDLE" >&2; exit 1; }
TOKEN="$(awk -F'"' '/ORACLE_TOKEN/{print $2; exit}' "$BUNDLE/environment/docker-compose.yaml")"
[ -n "$TOKEN" ] || { echo "cannot read ORACLE_TOKEN from $BUNDLE compose" >&2; exit 1; }
echo "converting $BUNDLE  (arvo_id=$ARVO_ID token=${TOKEN:0:8}...)"

# --- 1. task-server dir -----------------------------------------------------
mkdir -p "$BUNDLE/environment/task-server"
sed "s/@@ARVO_ID@@/$ARVO_ID/g" "$TPL/task-server.Dockerfile" > "$BUNDLE/environment/task-server/Dockerfile"
cp "$TPL/task_server.py" "$BUNDLE/environment/task-server/task_server.py"

# --- 2. docker-compose.yaml -------------------------------------------------
sed "s/@@AUTH_TOKEN@@/$TOKEN/" "$TPL/docker-compose.yaml" > "$BUNDLE/environment/docker-compose.yaml"

# --- 3. agent-side submit.sh (baked into the main sandbox image) ------------
cp "$TPL/submit.sh" "$BUNDLE/environment/submit.sh"

# --- 4. verifier ------------------------------------------------------------
mkdir -p "$BUNDLE/tests"
sed "s/@@AUTH_TOKEN@@/$TOKEN/" "$TPL/tests/test.sh" > "$BUNDLE/tests/test.sh"
cp "$TPL/tests/verify.py" "$BUNDLE/tests/verify.py"

# --- 5. drop the dead oracle dir -------------------------------------------
rm -rf "$BUNDLE/environment/oracle"

# --- 6. per-bundle run scripts (build.sh = public net, push.sh = upload net) ----
bash "$HERE/gen_scripts.sh" "$BUNDLE" "$VER"

# --- 7. normalize instruction.md (drop shared placeholder, prepend fixed PoC
#        preamble unless a similar instruction is already present) ------------
if [ -f "$BUNDLE/instruction.md" ]; then
  python3 "$HERE/normalize_instruction.py" "$BUNDLE/instruction.md"
fi

echo "  done: task-server/, docker-compose.yaml, submit.sh, tests/{test.sh,verify.py}, build.sh, push.sh, instruction.md; oracle/ removed"
