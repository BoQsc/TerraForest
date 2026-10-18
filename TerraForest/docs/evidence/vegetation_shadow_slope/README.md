# Sloped-world near-shadow check

2026-10-18. Readonly southern world; 1920x1080 fullscreen, cap60. Samples 64 natural support positions, selects a vegetation-bearing slope and teleports through normal terrain loading. Selected point (1106,59.43133,1786), surface slope 26.886 degrees. Production 4096 atlas and focused blended splits; normal bias remains2.0.

Shadow-on/off images inspected: real nearby cast shadows are visible and no obvious terrain acne appears in this view. Wind is frozen; camera fixed. Repeat shadow-on captures, after intervening shadow-off: only2 of1,152,000 pixels differ in the full-width y200..799 region (HUD/hands excluded). This demonstrates static repeatability, not shimmer-free moving projection. Toggle changed6.72% of pixels in that region; this is descriptive evidence, not a quality threshold. Comparison uses Pillow RGB absolute difference, counting pixels with any nonzero channel.

World loading, slope sampling and publication checks pass. This check does not qualify wind-enabled movement, every slope/sun angle, old-laptop thermal limits or locked60FPS. Capture readback affects displayed HUD FPS; no runtime timing conclusion is taken from these screenshots.

No production settings, models, density or user saves changed. The near-shadow correction is retained. Remaining moving-view shimmer verification and distant coverage/density/zoom work remain open in the world-building standard.
