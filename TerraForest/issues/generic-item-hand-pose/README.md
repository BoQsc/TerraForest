# Generic held-item hand posing

- Status: Baseline integrated; articulated revision 02 authored, player review pending.
- Updated: 2026-11-04. Original baseline source/preview: `bc5de4ae`.
- User review: Idea is great, but the arm/hand looks like a static stick. Requested committing/integrating that baseline and trying to improve it.
- Symptom: Almost-fixed fingers and an exactly neutral wrist make the palm-up lift read as a rigid platform.

## Images

![Committed baseline](../../docs/evidence/item_use/book-use.png)

Candidate 01 book use, controlled neutral Godot 4.7.2 Forward+ stage on RTX 4050;
75-degree 16:9 first person plus side/front body and underside grip views. No
world/seed or saved-player state. Original images, video and hashes remain in
[baseline evidence](../../docs/evidence/item_use/README.md).

## Changes and verification

The unchanged baseline library is now in runtime as `Human.item_hold.res`.
Existing six book/food meshes appear in the right hand; other ordinary items
use the original neutral fallback. Existing native item identity, metadata,
inventory, rewards, consumption and drops remain authoritative. One completed
world gesture commits one native use; UI/equip/focus/ownership changes cancel
pending use. [Integration and scoped checks](../../docs/evidence/item_use/integration/README.md).

## Remaining / resume here

Revision 02 adds finger readjustments, wrist articulation and a free-hand
approach, preserving the integrated baseline (`26f332e1`). Its 28 scoped checks
pass across 555 poses; wider contact checks exposed earlier clipping/separation
and the failed logs are preserved. [Revised preview, exact checks and limits](../../docs/evidence/item_use/revision02/README.md).

![Revision 02 book use](../../docs/evidence/item_use/revision02/book-use.png)

Same neutral stage/camera arrangement as the baseline; this is the revised
candidate's use pose with the free hand approaching beneath the closed book.
Obtain player review of hand readability, finger/wrist motion and timing before
promotion, then rerun live-world checks. Passing geometric checks does not
resolve the reported rigid appearance. Dedicated eating/page-turning and broad
third-person art acceptance remain separate. Reopen here on feedback.

## Reproduce / history

Equip a book/food in the real belt and left-click to use it. Candidate 01 remains
in `docs/evidence/item_use`; its editable sources remain in `authoring/Human.item_use.*`.
The art revision is stored separately as `Human.item_use_v2.*` and cannot silently
replace the runtime baseline. New motion/data/assets are CC0; new code is 0BSD;
inherited notices remain identified in the respective asset notices.
