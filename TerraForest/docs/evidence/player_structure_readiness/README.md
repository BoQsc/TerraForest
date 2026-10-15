# Player structure readiness

2026-10-15: `tests/player_structure_readiness.gd` passes in the normal world,
rendered fullscreen at 1920x1080 with a 60 FPS cap. See console.log and run.json.

The test delays native collision admission for one real window model near the
player, holds W once, and calls the production controller physics path. Four
ticks preserve position, zero velocity and held W. After native admission,
walking resumes without another press. Terrain readiness is checked separately.

This is a deterministic integration check, not dense-city continuous travel,
vehicle, multiplayer, frame-time or thermal qualification. The world is temporary;
the inherited 'ordinary compound save completes' label refers to shutdown and
does not prove persistence (the log explicitly records save skipped).
