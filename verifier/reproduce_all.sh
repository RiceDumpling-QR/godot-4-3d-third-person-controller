#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFIER_ROOT="${REPO_ROOT}/verifier"
RESULTS_ROOT="${VERIFIER_ROOT}/results"
GODOT_BIN="${GODOT_BIN:-godot}"

MAIN_REF="${MAIN_REF:-main}"
TASK_REF="${TASK_REF:-task/locomotion}"
CLAUDE_1_REF="${CLAUDE_1_REF:-run/claude-1}"
CLAUDE_2_REF="${CLAUDE_2_REF:-run/claude-2}"
CLAUDE_3_REF="${CLAUDE_3_REF:-run/claude-3}"

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/roboblast-reproduce.XXXXXX")"
STAGED_RESULTS="${WORK_ROOT}/results"
mkdir -p "${STAGED_RESULTS}"

cleanup() {
  rm -rf "${WORK_ROOT}"
}
trap cleanup EXIT

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

require_ref() {
  if ! git -C "${REPO_ROOT}" rev-parse --verify --quiet "${1}^{commit}" >/dev/null; then
    echo "Git ref not found: $1" >&2
    exit 1
  fi
}

copy_verifier() {
  local snapshot="$1"
  mkdir -p "${snapshot}/verifier/results"
  rsync -a \
    --exclude '.DS_Store' \
    --exclude 'results/' \
    "${VERIFIER_ROOT}/" "${snapshot}/verifier/"
}

export_snapshot() {
  local ref="$1"
  local name="$2"
  local snapshot="${WORK_ROOT}/${name}"

  mkdir -p "${snapshot}"
  git -C "${REPO_ROOT}" archive "${ref}" | tar -x -C "${snapshot}"
  copy_verifier "${snapshot}"
  printf '%s\n' "${snapshot}"
}

run_snapshot() {
  local snapshot="$1"
  local label="$2"
  local output_name="$3"
  local skip_import="${4:-0}"

  echo
  echo "==> ${label}"
  if [[ "${skip_import}" == "1" ]]; then
    SKIP_IMPORT=1 GODOT_BIN="${GODOT_BIN}" \
      "${snapshot}/verifier/run_verifier.sh" \
      "res://verifier/results/${output_name}" "${label}"
  else
    GODOT_BIN="${GODOT_BIN}" \
      "${snapshot}/verifier/run_verifier.sh" \
      "res://verifier/results/${output_name}" "${label}"
  fi
  cp "${snapshot}/verifier/results/${output_name}" "${STAGED_RESULTS}/${output_name}"
}

for command_name in git tar rsync jq; do
  require_command "${command_name}"
done
if [[ ! -x "${GODOT_BIN}" ]] && ! command -v "${GODOT_BIN}" >/dev/null 2>&1; then
  echo "Godot executable not found: ${GODOT_BIN}" >&2
  exit 1
fi

for ref in "${MAIN_REF}" "${TASK_REF}" "${CLAUDE_1_REF}" "${CLAUDE_2_REF}" "${CLAUDE_3_REF}"; do
  require_ref "${ref}"
done

original_snapshot="$(export_snapshot "${MAIN_REF}" original)"
run_snapshot "${original_snapshot}" original original.json

ablated_snapshot="$(export_snapshot "${TASK_REF}" ablated)"
run_snapshot "${ablated_snapshot}" ablated ablated.json

claude_1_snapshot="$(export_snapshot "${CLAUDE_1_REF}" claude-1)"
run_snapshot "${claude_1_snapshot}" claude-1 claude-1.json

claude_2_snapshot="$(export_snapshot "${CLAUDE_2_REF}" claude-2)"
run_snapshot "${claude_2_snapshot}" claude-2 claude-2.json

claude_3_snapshot="$(export_snapshot "${CLAUDE_3_REF}" claude-3)"
run_snapshot "${claude_3_snapshot}" claude-3 claude-3.json

probe_results=()
for probe in world-relative fast-diagonal instant-velocity infinite-jump no-rotation; do
  probe_snapshot="${WORK_ROOT}/probe-${probe}"
  cp -R "${original_snapshot}" "${probe_snapshot}"
  git -C "${probe_snapshot}" apply "${VERIFIER_ROOT}/probes/${probe}.patch"
  run_snapshot "${probe_snapshot}" "${probe}" "${probe}.json" 1
  probe_results+=("${STAGED_RESULTS}/${probe}.json")
done

jq -s '
  def lost($check_name):
    any(.checks[]; .name == $check_name and .points < .maximum);
  {
    all_caught: (
      (.[0] | lost("camera_relative_movement")) and
      (.[1] | lost("diagonal_normalization")) and
      (.[2] | lost("acceleration")) and
      (.[2] | lost("stopping")) and
      (.[3] | lost("midair_jump_rejection")) and
      (.[3] | lost("stable_landing")) and
      (.[4] | lost("travel_orientation"))
    ),
    probe_count: length,
    probes: .
  }
' "${probe_results[@]}" > "${STAGED_RESULTS}/probe-results.json"

if ! jq -e '.all_caught == true' "${STAGED_RESULTS}/probe-results.json" >/dev/null; then
  echo "At least one near-miss probe escaped its intended verifier check." >&2
  exit 1
fi

# Publish only after every run succeeds, so a failed reproduction cannot leave
# a mixture of old and new canonical results.
mkdir -p "${RESULTS_ROOT}"
for result in original.json ablated.json claude-1.json claude-2.json claude-3.json probe-results.json; do
  cp "${STAGED_RESULTS}/${result}" "${RESULTS_ROOT}/${result}"
done

echo
echo "Reproduction complete. Canonical results:"
for result in original.json ablated.json claude-1.json claude-2.json claude-3.json; do
  jq -r '"  \(.label): \(.score)/\(.maximum)"' "${RESULTS_ROOT}/${result}"
done
jq -r '.probes[] | "  probe \(.label): \(.score)/\(.maximum)"' \
  "${RESULTS_ROOT}/probe-results.json"
