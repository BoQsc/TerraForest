# Extended vegetation LOD and approximate self-shading

2026-10-18. Engineering evidence, not final world-quality acceptance.

Near geometry and candidate distribution are unchanged. Grass retains 468/72/8 triangle tiers and adds a 3-triangle outer tier. Coverage fades from 100 to 124 metres; 81 owners replace 49. Native picker capacity follows the same bounded owner count. Near cast-shadow settings remain 24 metres for grass and 48 metres for other cover (page bounds and padding apply).

Distant foliage receives root-weighted approximate self-shading over 24–56 metres. This is a shader colour multiplier, not a projected ground shadow. It introduces no texture sample or shadow-map pass. It does not meet every possible distant-shadow requirement.

Both native debug/release builds succeeded. Scatter, stream, picker and mesh-LOD checks pass. The original 49-owner picker cap failed the expanded stream test; that evidence is retained, and the bounded cap was corrected to 81. Other fixture owner expectations were updated but those fixtures were not all rerun.

Integrated readonly southern-world check: 22.033 seconds to settle after arrival, frame median 16.649 ms, p95 18.181 ms, worst 18.672 ms. Observed resident transform payload 4,864,064 bytes. Grass budget 7 MB; per-tick upload budget unchanged. All owners settled without budget deferrals.

Sequential shader comparison GPU medians: enabled 7.489 ms, disabled 8.084 ms. This is not evidence of a speedup; sample/order variance exceeds any established cost difference. Images ground/overview/canopy_off were inspected. The visual shading change is subtle.

Scripted 64 m camera travel at 6.4 m/s passed streaming checks: frame p95 17.953 ms, worst 34.591 ms. travel_end was inspected. This is not long-run, player-navigation, locked-60-FPS or older-laptop thermal qualification. Screenshot readback is outside the timed windows.

Open: slow population of the larger area (sequential terrain support sampling), frame-time tails, visual transition/density acceptance against the woodland showcase, and zoom-aware distant coverage. Do not reduce near density to conceal these limits. Existing user saves were not changed.
