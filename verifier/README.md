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

The command runs without opening the editor, prints an itemized score out of 100, writes JSON, and exits. Candidate gameplay failures receive partial or zero points; verifier crashes are execution failures.

## Scoring

| Observable outcome | Points |
|---|---:|
| Four-direction ground movement | 15 |
| Camera-relative direction | 20 |
| Diagonal speed normalization | 10 |
| Gradual acceleration | 10 |
| Stable deceleration and stop | 10 |
| Visible facing follows travel | 10 |
| Grounded jump | 10 |
| Midair jump rejection | 5 |
| Held jump exceeds tapped jump | 5 |
| Stable landing | 5 |

The grader drives the configured input actions in a controlled flat scene and measures displacement, velocity, orientation, jump height, and grounded state. It does not search source text or require particular function names.

## Recorded validation

- Original implementation: 100/100.
- Ablated task: 12/100; it launches, but earns no movement or jump implementation credit.
- Near-miss probes: 80–90/100, with every deliberately defective solution rejected.

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
