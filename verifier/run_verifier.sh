#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
OUTPUT_PATH="${1:-res://verifier/results/latest.json}"
LABEL="${2:-candidate}"

# A clean Git checkout has no .godot/imported cache. Import project assets first
# so results do not depend on whether the checkout was previously opened locally.
if [[ "${SKIP_IMPORT:-0}" != "1" ]]; then
  "${GODOT_BIN}" --headless --editor --quit --path "${PROJECT_ROOT}"
fi

"${GODOT_BIN}" --headless --path "${PROJECT_ROOT}" \
  --script res://verifier/locomotion_verifier.gd \
  -- --output "${OUTPUT_PATH}" --label "${LABEL}"
