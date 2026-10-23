# Compact centered loading panel

2026-10-23. Generation and gameplay loading now default to a centered 1120-pixel
panel at 1920x1080. It retains the existing slim bar, timers, stage details and
cancel/quit action. The Compact switch turns this off for the previous 90% width.
The choice is saved in user://loading_presentation.cfg and read by new panels,
including the separately launched generator and game. Toggling does not reset
elapsed time or progress. The full developer panel stays independently scrollable.

The existing rendered loading check passed: default and optional widths, centering,
non-overlap, actual loading counters/timers, gameplay readiness and stopped timer
polling. An isolated preference file verifies the real toggle and restoration by a
new panel, preserving the user's preference. The three PNGs were inspected at
1920x1080. This presentation-only change does not modify world generation, data,
readiness gates or native binaries; broader foundation gaps remain open.

The package was rebuilt (250,743,980 bytes); its startup smoke check passed with
14 external native libraries. The rendered checks above ran from source.
