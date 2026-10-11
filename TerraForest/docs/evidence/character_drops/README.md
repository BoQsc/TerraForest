# Character equipment and outside-UI stack drops

2026-10-11: main-scene character_drops 25 checks passed, native inventory_drop
16 passed, reward_claim_ui 14 passed. Fullscreen graphics at 1920x1080, cap 60;
not sustained frame-time or thermal qualification. Screenshots inspected.

Crafting/Character buttons above the left panel switch its contents. Character
has Head, Body and Feet clothing slots. Woven hood/vest/footwraps are craftable
from 2/4/3 plants. NativeContainerStore holds equipment separately under the new
player_equipment save component. Typed UI targets reject tools and wrong-slot
clothing. Drag back to backpack/belt to remove. Clothing has no armor stats or
worn-model visuals yet. No character meshes are claimed by this UI change.

Removed Equip selected and Drop one buttons. Toolbelt remains quick-use storage.
A separate input-only drop surface behind HUD controls receives outside releases;
there is no background tint. Panel whitespace cancels drops. Focus, supported
clear ground, collision readiness and overlap checks still gate world drops.
Shift-drag carries half, otherwise the full dragged stack. All carried items,
including tools and new clothing, have pickup support.

One stack occupies one NativeEntityStore record and one sparse native container,
not one entity per item. Native transfer commits counts before change callbacks;
spawn rollback preserves inventory on refusal. Per-item pickup_stacks sections
persist quantities; legacy/authored pickups without stack metadata remain one
unit. All component sections plus terrain remain below the 64-section archive
limit. Pickups retain the existing simple box mesh, no active rigid bodies.

Real mouse tests cover tabs, invalid equipment targets, crafting clothing,
equip/unequip, equipment snapshot round-trip, outside releases, panel cancellation,
focus rejection, 64-item stack/recollection, half-stack drops, overlapping-ground
rejection and tool dropping. Native drop checks cover stale revisions, reentrant
requests, capacity failures and legacy missing-component defaults.

Earlier attempts caught a duplicate local declaration and CRLF fixture error;
these were repaired before successful runs. Tests use temporary worlds only.
