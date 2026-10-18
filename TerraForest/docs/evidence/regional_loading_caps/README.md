# Loading frame-cap diagnosis — 2026-10-18

The preceding supplies check sometimes exceeded a 60-second loading deadline.
A read-only trace reproduced it: terrain and 9/9 local collision probes were ready,
all four cached lakes were restored, but water surface publication was incomplete.
Dirty surfaces decreased continuously from 2,581 at 7 s to 284 at 60 s. This was
ongoing work, not a stopped worker or lost terrain readiness.

The initial trace did not record the active frame cap. Production uses 15 FPS
when unfocused, and the supplies test had not overridden background_fps, unlike
the preparation and mine checks. Water publication has a per-frame soft time budget
and a four-packet ceiling. Consequently focus changes can greatly affect elapsed
startup time even with identical saved/cache data.

Controlled follow-up: same published world, force both active/background caps to
15, switch both to 60 after 15 seconds, without resetting any world state. The trace
records actual cap/FPS and every readiness gate. Publication rises from roughly
40 regions/s to 170 regions/s; all readiness gates complete and the process passes
in 29.51 s. This establishes frame-cap sensitivity, though the missing cap in the
original failed run prevents claiming its focus history was directly observed.

The supplies test now uses a fixed 60 FPS cap in either focus state, matching
other graphical automated checks. Production background power saving, water mesh
budgets and readiness requirements are unchanged. The new trace can be rerun with
`--loading-cap-comparison` and the same read-only saved-world arguments as supplies.

This does not fix the separately observed runtime frame spikes, qualify sustained
performance, or make cold/cached world loading instantaneous. Cached water still
requires substantial surface publication at startup; that remains an architectural
loading cost rather than a deadlock demonstrated by this evidence.
