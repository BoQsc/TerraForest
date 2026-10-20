# Destination collision readiness - 2026-10-20

Actual populated-world paging route (central/north/south/central), 1920x1080
fullscreen, 60 FPS cap, read-only disposable copy paging_integrated_20261020.
Test: tests/populated_model_paging.gd. Comparison manifest covers 995 saved models.

Original check failed northern arrival: loading released with local structure
collision unavailable and 325 nearby model records still absent. Zero pending
render uploads did NOT mean readiness: unloaded model records had not queued any.
Original failure and corrected run retained here.

Production _additional_loading_ready now requires native structure AND vegetation
collision readiness in a 4 x 5 x 4 m departure box around the player, before its
existing water readiness check. The existing three-frame stability requirement
and per-physics-tick swept motion guards remain. No busy wait or new world scan
is introduced in script; occupancy queries remain native.

Corrected four-arrival route passes local collision availability at loading
release, exact nearby saved transforms after admission, distant retirement and
zero failed transfers. The default non-model-paged startup is also checked.

Important remaining gap: the local collision gate does not guarantee that all
visible model records or render pages are present. Missing-at-release counts in
the result explicitly retain this limitation. Add bounded native visual-region
readiness covering unloaded metadata and published render pages before enabling
model paging by default; pending upload counts alone are insufficient.

Frame samples are 120 frames after nearby record admission; they exclude loading
and are not whole-travel performance or sustained qualification. Arrival timings
include terrain loading. No visual acceptance or high-speed vehicle readiness is
claimed. Existing player saves were not modified.
