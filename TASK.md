# Restore Third-Person Locomotion

Restore the player's complete locomotion experience while keeping combat, camera control, collectibles, enemies, and the rest of the demo working as they do now.

## Required behavior

- The movement controls move the player across the ground relative to the camera's horizontal facing direction. Forward should always mean away from the camera, even after the camera turns.
- Movement supports every direction, including diagonals, without diagonals being faster than movement along a single axis.
- The player builds up to full running speed smoothly and slows to a stable stop when movement is released. Full running speed should remain consistent with the original feel of the demo, approximately 8 world units per second.
- The visible character turns smoothly toward the direction of travel and retains a stable facing direction while standing still.
- Starting a melee attack temporarily prevents directional movement from overriding the attack motion.
- Jumping begins only while grounded. A press gives an initial upward launch, and continuing to hold jump while rising produces a moderately higher jump than a quick tap.
- Repeated jump presses in midair do not create additional jumps. After reaching the apex, the player falls naturally and settles reliably on the ground.
- The visible character transitions appropriately between standing, moving, jumping, and falling. The movement animation reflects current horizontal speed rather than playing at one fixed intensity.
- Footstep feedback occurs in sync with steps while moving, and landing feedback occurs once when returning to the ground.
- Movement remains collision-aware and stable against level geometry; the player should not pass through obstacles or remain trapped while trying to move along them.

Do not remove or weaken unrelated gameplay systems to complete the task.

## Evaluation isolation

Complete the task using only this prompt and the files already present in the current checkout.

- Do not inspect or recover an implementation from Git history, commits, tags, remotes, other branches, stashes, reflogs, or deleted objects.
- Do not read parent or sibling directories, other local copies of this project, previous agent attempts, or external implementations of this demo.
- Do not use the internet or external source-code search to find the removed locomotion implementation.
- Do not search for or access hidden verifier code, test scenes, grading results, anti-cheat probes, or reference patches.
- Do not switch branches, merge, rebase, reset to another revision, or otherwise replace this checkout with code from outside it.

You may inspect and edit any project file inside this checkout and may run Godot, project-local tools, and your own diagnostic commands within it. Implement the behavior independently, then report the files you changed and the validation you performed.
