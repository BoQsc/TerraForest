# Building review

## Mixed neighborhood checkpoint

**Review Mixed Neighborhood.cmd** prepares and opens `mixed_neighborhood_review`
only if that save is absent. It combines five cottages and three furnished
three-floor towers with connected asphalt streets, forest and normal gameplay.
Doors use E; F5 saves. The existing cottage, tower and gameplay saves are preserved.
The first preparation includes cold world/cache generation and can take minutes;
later launches reuse the saved world. It runs at 1920×1080 with a 60 FPS cap.

All eight entrances passed actual player walking from the street through the
opened doors. Exact blocks, furnishings, windows, doors, guardrails and roads
survived a fresh-process reload. This is a small playable neighborhood, not a
large-city or sustained-performance qualification. See
[evidence and limitations](evidence/mixed_neighborhood/README.md).

## Cottage checkpoint

To create your own layout, enable development mode with **~**, open **Esc →
Building → Create streets / settlement from prefabs**, then choose **Cottage
neighborhood** or **Mixed neighborhood**. Name it in the dialog and click building
types to include/exclude them; Ctrl is no longer required. Street count, density,
width, gap and seed remain editable. **Create and save layout** creates a reusable
prefab. Return to the world, aim at terrain, then use **Survey ground**, **Prepare
foundation** and **Place prefab** through the existing building controls.

Run **Review Buildings.cmd** from the TerraForest folder. It opens the separate
`building_review` save at 1920×1080 with the normal 60 FPS target. An existing
review save is reused, never replaced. If absent, the launcher prepares and checks
a unique clone before publishing the review copy. `combined_gameplay` is untouched.

You start inside the newly grounded cottage, near its entrance. Aim at the wooden
door and press **E** to open/close it. Walk through the entrance and down the stairs,
inspect the windows, furniture and chest. Step clear of the door swing if prompted.
Normal attacks can destroy the whole window or door; separate glass-only breakage,
door animation and locks are not implemented. F5 saves your review-world edits.

The prefab is also available as **Furnished cottage with door and windows** in the
building catalog. Its foundation now starts at local Y=0 for editor site preparation.
Existing placed buildings and original cottage assets are unchanged.

Automated evidence: [grounded building checks](evidence/building_review/README.md).
This checkpoint covers one furnished cottage, not finished city or tower content.

## Tower checkpoint

**Review Tower.cmd** opens a separate `tower_review_guarded` save beside the three-floor
furnished tower's entrance. Press E while aiming at the door. Inside, use the
central stair flight, walk around its east landing, and take the next flight to
the third floor. Floors have tables, chairs, shelves and chests. F5 saves this
review world. The cottage checkpoint is separate and is not overwritten.

Main-world automated walking reached the third floor and returned downstairs;
door/window state survived a fresh-process restart. This is not a large-city
performance qualification. Upper stairwell guards are now included; further
interior detail remains unfinished. The previous `tower_review` save is preserved.
The automated exterior image is obscured by nearby foliage, so human
visual feedback is still needed.
