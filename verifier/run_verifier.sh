#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
OUTPUT_PATH="${1:-res://verifier/results/latest.json}"
LABEL="${2:-candidate}"

"${GODOT_BIN}" --headless --path "${PROJECT_ROOT}" \
  --script res://verifier/locomotion_verifier.gd \
  -- --output "${OUTPUT_PATH}" --label "${LABEL}"
