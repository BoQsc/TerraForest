# Grounded building review — 2026-10-15

Command: `python tools/check_enclosed_cottage.py --grounded`

In a unique source-world clone, the normal editor surveyed terrain, graded the
foundation and placed the complete cottage through the supported prefab pipeline.
Actual capsule walking passes through its open door; the closed door blocks it.
Ordinary save and a fresh process preserve exact door pose/hinge state and eight
window identities. E closes the reopened door. Source canonical hash unchanged.
The successful save was published as `building_review` without overwriting any
existing review slot. `Review Buildings.cmd` opens this human-review checkpoint.

The first test exposed the negative-Y foundation origin inherited from the old
cottage. Native composition now raises the new variant's blocks and attachments
together by one metre, preserving all relative geometry. The second test waited
for nearby collision while the player was still at the old site, over 64 m away;
moving the test player to the entrance before readiness follows normal residency.
Both failed logs are retained.

Inspected `grounded.png`: cottage and stairs meet the graded stone foundation;
windows fit the wall openings. The red outline is the active editor prefab preview
at capture time. The saved review starts back in gameplay mode. The image is not
a benchmark: startup receive hitches remain in logs, and neither thermal behaviour
nor large-scale building performance is qualified here. Human review remains open.
