# Current combined gameplay regression

After native building idle-selection and local-readiness changes, one complete
mixed-world route ran from a fresh copy of immutable staging slot
`combined_stage_7801173ed84740ee91a1b06e51a3298b`. The canonical source hash remained
unchanged. Existing saved towers retain their original attachments; this route
does not exercise newly authored stair rails.

All three graphical phases pass at 1920x1080 fullscreen/full scale/cap60:

- Resource route, 14.17 s: gather natural stones, craft, paid block placement,
  chest deposit/withdraw, compound save.
- Travel, 28.75 s: walk out through the cottage door and stairs; spawn/enter car,
  drive 12.02 m, brake, reverse and stop within the unchanged <3 m gate (2.55 m),
  exit and walk back. No vehicle pose correction or inventory grant.
- Fresh reopen, 13.01 s: exact inventory, chest, harvested identities, placed
  brick and door state; chest interaction and nonempty removal protection.

Report `reports/combined_resource_route/20261015T214728031665Z`. Reverse telemetry
now records actual window focus, application focus, physics frame and wall time
alongside keys, support, freeze and drive speed. Samples show active focus/input,
four loaded wheels and no streaming hold. The old intermittent reverse failure
did not recur; this is not a vehicle fix and that earlier failure remains open.
Do not repeat unchanged looking for a greener result.

Terrain receive hitches were 133.71 / 159.9 / 141.11 ms across the phases. Thus this
is a functional integration pass, not sustained performance or loading closure.
Gathering uses fixture relocation; the driven segment is short. High-speed,
long-distance, dense populations, thermal and multiplayer gates remain open.
