# Pickaxe integration authorized for commit and terrain sync

On 2026-10-23 the user explicitly requested committing and syncing the animation
work into `codex/foundation-vegetation-support`. This supersedes the earlier
no-commit gate. Historical source metadata and review evidence remain intact.

The selected default is the deeper-pullback side strike the user reviewed as
better: `FP_Pickaxe_SidePullback_Swing`. Diagonal idle/locomotion holds remain.
The 1.2-second action returns to its ready grip. `pickaxe_swing="diagonal"`
selects the earlier forward strike; `diagonal_pickaxe=false` selects original
pickaxe actions. Empty hands stay idle between actions.

The earlier side-strike and latest five-degree-right arc-swing copies remain
available with editable Blender source and review videos. The latest arc swing
still awaits visual acceptance and is not the default. Rejected experiments are
preserved under ignored evidence archives, outside active runtime assets.

Checks retained under `checks/` pass for character runtime, the arc-swing copy,
pullback comparison and the earlier diagonal swing in a temporary world. The
focused player-runtime package check also passes, including the selected library.
An initial alternate test attempted to attach the now-default AnimationLibrary
twice; test libraries now duplicate their container before attaching, resolving
the signal connection errors. No animation asset rebake was required.

The actual-world placement suite confirms the selected default swing starts and
returns to ready, and block-placement/empty-idle lifecycle checks pass. Its broader
terrain-fill-feedback assertion remains failing: an isolated sample is admitted,
but the gesture is inactive after consumption. That failure remains visible in
`placement_open_failure`, and is not overridden by animation-only checks. A
headless viewport-size assertion was corrected by declaring the intended
1920×1080 test viewport; earlier failures remain in the check reports.

This commit changes camera-local presentation and tests. It does not change
terrain/native code, actor movement, navigation, mining damage/cadence or saves.
The terrain checkout's pre-existing `project.godot` edit is preserved on sync.
