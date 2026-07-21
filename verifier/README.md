# Locomotion verifier

This directory contains the hidden, outcome-based grader for the third-person locomotion task. Do not include it in an agent rollout workspace.

## Run

From the repository root:

```bash
GODOT_BIN=/path/to/Godot verifier/run_verifier.sh
```

Optionally choose an output resource path and label:

```bash
GODOT_BIN=/path/to/Godot verifier/run_verifier.sh \
  res://verifier/results/my-run.json my-run
```

The runner first imports project assets, then runs without opening the editor. It prints an itemized score out of 100, writes JSON, and exits. Candidate gameplay failures receive partial or zero points; verifier crashes are execution failures. Set `SKIP_IMPORT=1` only for a snapshot whose `.godot/imported` cache is already complete.

## Reproduce the complete evaluation

From the verifier branch, regenerate every canonical result from clean Git snapshots:

```bash
GODOT_BIN=/path/to/Godot verifier/reproduce_all.sh
```

The script exports `main`, `task/locomotion`, and `run/claude-1` through
`run/claude-3` without using their worktrees. It overlays the current hidden verifier,
runs every target, applies each probe independently to a clean original snapshot, and
publishes `verifier/results` only after all runs succeed. It requires `git`, `tar`,
`rsync`, and `jq`.

The ref names can be overridden when needed, for example:

```bash
MAIN_REF=origin/main TASK_REF=origin/task/locomotion \
  GODOT_BIN=/path/to/Godot verifier/reproduce_all.sh
```

## Scoring

| Observable outcome | Points |
|---|---:|
| Four-direction ground movement (3 points per correct direction) | 12 |
| Camera-relative direction | 15 |
| Diagonal speed normalization | 8 |
| Gradual acceleration | 8 |
| Stable deceleration and stop | 8 |
| Visible facing follows travel | 8 |
| Grounded jump | 9 |
| Midair jump rejection | 4 |
| Held jump exceeds tapped jump | 4 |
| Stable landing | 4 |
| Collision blocking and wall sliding | 7 |
| Locomotion animation transitions | 5 |
| Footstep and landing feedback wiring | 3 |
| Camera control and melee attack preservation | 5 |

The grader drives the configured input actions in controlled flat and collision scenes. It measures displacement, velocity, orientation, jump height, grounded state, collision response, animation state, feedback wiring, camera yaw, and attack state. Basic movement scores each direction independently. Movement-dependent checks are gated so an inert player cannot earn stopping or jump-safety credit merely by remaining still. It does not search source text or require particular function names.

## Recorded validation

- Original implementation: 100/100.
- Ablated task: 7.5/100; it launches and preserves unrelated gameplay, but earns no locomotion or jump credit.
- Near-miss probes: 85–92/100, with every deliberately defective solution losing the points tied to its defect.

Probe patches and captured results are stored under `probes/` and `results/`.
Each probe applies independently to the original working game; do not stack them.
For example:

```bash
git apply verifier/probes/no-rotation.patch
GODOT_BIN=/path/to/Godot verifier/run_verifier.sh \
  res://verifier/results/no-rotation.json no-rotation
git apply -R verifier/probes/no-rotation.patch
```

`results/probe-results.json` contains the full itemized output for all five probes and an
`all_caught` summary flag. The probe patches and verifier must remain unavailable to the
repair agent during evaluation.
