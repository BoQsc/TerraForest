# Woody bush integration — 2026-10-18

New species 8, item 212. Shared existing bush geometry stretched 1.4x vertically,
about twice grass height; original low bush remains. Native scatter, picker and
state expanded to nine species. Two accepted attacks grant one wood, including
empty hands. E collection cannot bypass damage. All four tools wear once per hit.
No per-instance bodies or scripts. Existing near cast-shadow band and fading apply.

Checks: native stream/scatter/picker/state and woodland geometry pass. Version 3
roundtrip and old version 1/2 loading covered. Baked icon and drop model are static
assets. Only the new drop mesh was baked; previous item atlas positions retained.

Readonly southern saved-world check at fullscreen 1920x1080: 399 natural woody
bushes present in resident area. Each tool and empty hands tested through the real
world attack target/apply path, native inventory, durability, picker and render
collections. First hit retains the bush/no reward, durability snapshot restores,
second hit removes the exact bush/grants one wood. Stale targeting cannot grant
again. Inventory placement and baked asset availability checked as well.

Before image inspected: larger leafy woody silhouette alongside normal grass,
grounded with cast shadow. This reuses the accepted low-bush art family; it is not
new final botanical artwork. Human appearance acceptance remains open. No timed
performance comparison or laptop thermal claim is made by this short check.

Initial world fixture queried terrain before its local ray was ready; retained
failed log. It now waits for the actual terrain query before creating the fixture.
Initial legacy-state assertion compared a cached v1 snapshot against v3 bytes;
fixed to compare the original v1 bytes, preserving the compatibility assertion.

Taller overlap checks apply only to species 8 on owner publication, so existing
low vegetation retains its previous structure-clearance bounds. Natural population
uses existing candidate IDs and replaces a small grass subset rather than adding
candidates. No old save files were written by this check.
