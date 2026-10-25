# Saved shoulder rejection — 2026-10-25

Source: the user's F5 save in `GridPreference_1703_2756a200` after playtesting
commit 8d9a6825. The player is at (951.6663,35.641,1139.778), yaw -0.755,
pitch -0.5625. The ordinary green cube target is (953,35,1137).

Nine actual collision samples measure 35.298618–35.398205 m. Integer base 35
buries the cube by up to **39.82 cm**; base 36 would leave up to **70.14 cm gap**.
Neither meets the diagnostic 10 cm gap / 25 cm burial limits. The audit correctly
reports `fits_any_integer_cell=false` and `quality_accepted=false`.

This point is 3.55 m from the settlement road center, outside its 3 m asphalt
half-width but inside the 5.5 m soil support. Neighboring curved road/support
stamps agree on approximately 35.35 m there. It is a transition from street level
36 to 35, not a disagreement between overlapping stamps. The standard analytic
road coverage omitted this shoulder; it was never an all-surface guarantee.

`result.json` retains the exact pose, ordinary target, contact feasibility and
nearby earthwork descriptors. `run.json` records successful read-only reproduction,
unchanged source/Wild_Hills hashes, and explicit quality rejection. No production
generation or placement settings are changed by this audit. This saved case must
remain a regression fixture for any proposed final-surface rule.

The audit's new stamp diagnostic follows the full piecewise curve through rounded
caps, matching native road_bed_field evaluation. Extrapolating each small cubic
independently would incorrectly suggest disagreement between adjacent stamps.
