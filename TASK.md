# Restore Third-Person Locomotion

## Goal

Restore the player's complete third-person locomotion while preserving combat, camera control, collectibles, enemies, and all other existing gameplay.

## Acceptance criteria

### Movement

- WASD movement works in every direction and is relative to the camera's horizontal facing. Forward always moves away from the camera.
- Diagonal movement is not faster than movement along one axis.
- The player accelerates smoothly to approximately 8 world units per second and decelerates to a stable stop.
- The visible character turns smoothly toward movement and keeps a stable facing direction while idle.
- A melee attack temporarily prevents movement input from overriding its attack motion.

### Jumping

- Jumping starts only while grounded; midair presses cannot create additional jumps.
- A press provides the initial launch. Holding jump while rising produces a moderately higher jump than tapping it.
- The player falls naturally after the apex and lands reliably without bouncing or hovering.

### Animation, feedback, and physics

- The visible character transitions correctly between idle, moving, jumping, and falling.
- Movement animation intensity reflects horizontal speed.
- Footstep feedback stays synchronized with steps, and landing feedback occurs once per landing.
- Movement remains collision-aware and stable around level geometry. The player must not pass through obstacles or remain trapped while sliding along them.

Do not remove, bypass, or weaken unrelated gameplay systems.

## Evaluation isolation

Use only this prompt and files inside the current checkout. Implement the locomotion independently.

Do not:

- Recover code from Git history, commits, tags, remotes, branches, stashes, reflogs, or deleted objects.
- Read parent or sibling directories, other project copies, previous agent attempts, or external implementations.
- Use the internet or external code search to locate the removed implementation.
- Search for or access hidden verifiers, test scenes, grading results, probes, or reference patches.
- Switch branches, merge, rebase, reset, or replace this checkout with another revision.

You may inspect and edit any file inside this checkout and run Godot, project-local tools, and diagnostic commands within it.

## Completion report

When finished, summarize:

1. Files changed.
2. Behaviors implemented.
3. Validation performed and any remaining limitations.
