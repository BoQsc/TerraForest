# Foundation cut shoulders — 2026-10-18

Native graded beds previously tapered added fill but excavated clearance with zero
shoulder, leaving vertical cut sides in higher substrate. Excavation now uses the
same bounded footprint with the opposite slope: its lower surface rises from the
flat pad to the clearance height at the outer shoulder. Fill still slopes downward.
Zero-shoulder roads retain their previous geometry. Existing snapshots are not
regenerated. No storage format, mesher, runtime simulation or SDK change.

Native density checks cover fill/cut interiors, flat pad, tapered sides/end caps,
unchanged outside field, idempotence, invalid-input preservation and exact snapshot
roundtrip. Graded-bed material/snapshot and road-bed checks pass. District plans
pass four rotations. Both debug/release extensions built with Zig/prebuilt godot-cpp.
The first cut fixture put its end-cap assertion on the substrate boundary; widening
that fixture made the assertion test excavation inside existing solid material.

A new full seed-42 district world was prepared and reopened as
graded_district_42_20261018. Creation/reopen and graphical district review pass with
building counts [8,5,2,12,4]. Screenshot inspected at 1920x1080. This north site is
predominantly fill: raised pavement edges and terraced foundation shoulders remain
visible. This fix addresses cut-side behavior, not all landscape integration.
No new sustained performance claim. Original named worlds remain untouched.
