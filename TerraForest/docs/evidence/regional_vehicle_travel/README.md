# Integrated regional vehicle travel

2026-10-18: saved district world, 1920x1080 fullscreen, capped at 60 FPS,
ground cover, forest, actors and native vehicle fleet enabled. Temporary read-only
session; one initial departure placement, no pose corrections after entry.

A full-throttle straight drive completed 574.52 m, reaching 158.28 km/h.
Zero render-frame samples reported collision streaming holds; p95 frame 17.669 ms,
maximum 18.465 ms. Full process took 44.35 s including load and shutdown.
Handbrake reached the test stop threshold of 0.15 m/s. The inspected screenshot
shows stopping beyond the approach on grass: no claim of controlled town arrival,
parking, cornering or acceptable stopping distance. No long-run or strict 60 FPS
qualification. Earlier intermittent frame issues remain open.

Reproduce: `python tools/check_regional_travel.py --vehicle` after closing other games.
Next useful vehicle coverage is controlled approach/braking, safe exit and building
entry; repeating this straight-line test would add little evidence.
