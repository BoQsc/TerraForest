# Furnished prefab admission scans - 2026-10-18

Direct furnished placement used the new staged transaction but still ran can_place_prefab over every block before beginning it. Preview also repeated that scan whenever the aim moved. Both duplicate scans are now bypassed for directly placed furnished prefabs. Native staged validation remains responsible for occupied cells and model conflicts. Player/vehicle bounds still reject early. The preview stays amber while placement checks are pending, and the UI legend now uses that wording rather than implying that only furnishing checks remain.

Frontage previews also remain amber without an eager cell scan; their existing foundation/admission path is unchanged. Block-only placement and its green/red occupancy preview are unchanged. Definition classification remains cached until source/world invalidation.

Actual-world real-ray test confirms that an obstruction in the bridge footprint reaches staged validation, then rejects without changing the obstruction, other structures or inventory. Removing it permits the existing two-slice publication of the deck and all six rails. Rotation cancellation continues to pass. Separate graphical preview checks pass for block-only green, furnished amber, player-overlap red, non-mutation and legend layout.

Reproduce: direct_prefab_staging --timeout 65 --require 'DIRECT_PREFAB_STAGING failures=0'; prefab_preview_feedback --timeout 65 --require 'PREFAB_PREVIEW_FEEDBACK failures=0', through tools/run_godot_check.py.

This removes known duplicate synchronous cell scans, not all synchronous work. Resource attachment copies, registry capture, final atomic publication and block-only/frontage admission remain separate costs. No measured FPS improvement or sustained city-scale qualification is claimed. Human saves and water unchanged.
