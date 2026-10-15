# Dense building collision relocation — 2026-10-15

Command: `python tools/run_godot_check.py tower_density --timeout 100 --require "TOWER_DENSITY failures=0" -- --collision-travel`

The real 64-tower fixture shifts block/model focus to four opposite grid corners
and back to the centre. Each probe covers a complete occupied tower, not an empty
street. Production `is_collision_region_ready` is false immediately at every new
target and becomes true after 32, 15, 6, 6 and 6 observation frames. At a nominal
60 Hz this is roughly 0.53/0.25/0.1 seconds, but wall-clock latency was not separately
measured. Cold collision readiness is therefore not instant.

Per-step model creation stays within the configured budget multiplied by actual
elapsed physics ticks; resident body/shape counts stay within caps. The original
test assumed one physics tick per observation, yielding a false budget failure
during a hitch. Its results/log remain retained. The corrected run passes both
relocation checks and the separate frame diagnostic (16.695 ms p95 in this run).
That passing frame result does not resolve earlier intermittent failures.

Source inspection confirms the normal player controller gates motion through
`_additional_motion_ready` after velocity calculation, and zeroes velocity when
unready. This test does not execute that controller gate: actual player freeze and
resume at a dense cold target is the next integration check. Nor does this qualify
vehicle travel, simultaneous players, network streaming or complete collision
coverage throughout the broader configured radius.
