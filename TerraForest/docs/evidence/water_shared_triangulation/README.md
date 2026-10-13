# Shared triangle generation — 2026-10-13

Terrain and water exposed top quads now call the same surface_quad template from the terrain surface helper. It retains terrain's clockwise winding and shorter-diagonal selection. Water no longer always splits its top quads along one fixed diagonal. Water side faces, connected-corner reconstruction and shoreline clipping remain water-specific; this is not a completed unified mesher.

The water build fingerprint now includes the imported shared terrain header, preventing stale incremental water builds after shared geometry changes. Both debug and release terrain/water DLLs rebuilt.

Validation: six quad cases cover both diagonals, flat tie and reversed winding; 32,768 representative cases and 7,168 connectivity cases pass. Six complete terrain packets still match pre-refactor terrain source. Release water continuity passes 14 assertions. The ordinary combined-world test passes all 46 assertions including held mining, consecutive excavation, buckets, exact water quantities and cached save/reload.

Actual-world outlet response was 1276 ms, frame median 16.666 ms, p95 16.8 ms, max 50.251 ms over 688 measured frames (screenshot readback excluded). These numbers are not a hardware-controlled improvement comparison or sustained-laptop qualification.

Visual inspection of water_repeated_mining.png still shows stepped/slatted edges along the mined bank. Shared triangulation is insufficient to resolve the visual defect. No finished-water claim. Terrain-contact reconstruction and connected surface sampling remain the next required integration work; the thin-interface adapter is not yet the runtime geometry provider.
