# Generated entrance regression

Initial test failed all four entrances: normal walking stopped at the door,
but E returned 'Step clear of the door swing'. The interaction supplied a
0.4 m half-width placement guard despite the actual capsule radius being
0.34 m, and the native door guard additionally inflated its bounds by 0.05 m.

Door interaction now uses the actual capsule envelope and uninflated merged
leaf bounds. No movement, door geometry or placement guard was changed.
Both Zig/prebuilt-SDK native targets compiled; runtime tests used debug.

After correction all four generated doors pass production held-W stair approach,
closed collision stopping, ordinary E interaction and interior walking without
jumping. Routes begin near each entrance; this is not continuous settlement
navigation. The independent door regression retains occupied-swing rejection,
snapshot restoration and 100-cycle stability checks. before.log is retained.

`python tools/check_enclosed_settlement_walk.py` clones combined_enclosed_review,
checks at fullscreen 1920x1080/cap60 and confirms the source canonical hash is
unchanged. Clones are retained. This is not a frame-performance or actor-route
qualification. Static obstacle/other actor swing protection remains outside the
current player-only protection contract.
