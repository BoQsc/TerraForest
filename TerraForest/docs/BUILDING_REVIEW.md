# Building review

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

**Review Tower.cmd** opens a separate `tower_review` save beside the three-floor
furnished tower's entrance. Press E while aiming at the door. Inside, use the
central stair flight, walk around its east landing, and take the next flight to
the third floor. Floors have tables, chairs, shelves and chests. F5 saves this
review world. The cottage checkpoint is separate and is not overwritten.

Main-world automated walking reached the third floor and returned downstairs;
door/window state survived a fresh-process restart. This is not a large-city
performance qualification. Stairwell guards and further interior detail remain
unfinished. The automated exterior image is obscured by nearby foliage, so human
visual feedback is still needed.
