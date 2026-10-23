# Full-resolution photographs and consistent loading dimming

2026-10-23. The photograph pipeline previously forced a 1920x1080 rendered frame
to 1280x720, then the loading UI enlarged it again. Capture now saves the original
lossless PNG without resizing: 2,073,600 pixels instead of 921,600, a 2.25x increase.
The loading TextureRect uses explicit linear filtering and displays at 1:1 pixel
size under the existing 1920x1080 fullscreen policy. Gameplay render scale, MSAA,
world assets and runtime rendering settings are unchanged. No extra viewport,
continuous capture or image-generation dependency is introduced.

Generation previously had no dim layer; gameplay loading had a separate 63% layer.
Both now use one shared static background component with a 50% dark tint. The
photograph is below the tint, and the title/progress/details are above it. The
original saved PNG remains undimmed. The background blocks clicks through to
underlying gameplay UI while loading. The Compact switch has been removed from
the loading screen; compact remains the default and the optional stored width
preference remains supported without an inline control.

Existing 720p preview sidecars remain valid. The world's read-only Refresh
photographs action recaptures them at full resolution; upscaling old pixels cannot
restore their missing detail. Larger PNGs increase photo storage/decoding cost;
this change prioritizes still-image fidelity and makes no loading-speed claim.

Verification:
- `refresh/`: the actual browser refreshes a disposable clone of an existing
  generated world. All three photographs and the selected Texture2D are 1920x1080;
  324 authoritative files remain byte-identical. Inspected the raw image and its
  dimmed loading presentation.
- `generation/` and `published_quality.json`: full creation/verification/publication
  passes. All three published photographs are 1920x1080 and byte-identical to the
  generator's source PNGs (no additional encoding or reduction).
- `reopen/`: fresh read-only full game opens that published world with the new
  background, reaches playable readiness, hits all four map caches and preserves
  its canonical save. The real loading screenshot was inspected.
- `ui/`: rendered 1920x1080 layout, absent Compact control, overlay placement and
  consistent tint, timers/counters, optional stored width, scroll and loading gates
  pass. Broader world art and runtime performance remain separate open requirements.

The first refresh invocation used a headless parent, but this updated test also
renders the resulting loading screen and requires frame_post_draw. It was stopped
after the capture child exited and rerun with a rendered parent. The failed wrong
invocation is retained in `headless_invocation/`; it is not a passing visual check.

Package rebuilt (250,744,072 bytes) and startup smoke passed with 14 external
native libraries. Full generation and rendered visual checks above ran from source.
