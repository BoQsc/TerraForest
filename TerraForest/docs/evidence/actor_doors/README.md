# Actor response to door changes

One native actor in a clone of the original generated enclosed settlement:
closed door blocks entry; opening via NativeHingedDoors allows route recovery
and arrival inside; closing blocks departure; reopening permits descent and
return. Production model-change signals invalidate routes; no explicit test
invalidation or actor relocation is used after spawning. Per-tick route work
remains <=12. Normal terrain/structure/vegetation readiness participates.

The fixture manually ticks the production actor adapter while player physics
is disabled, using the actual physics timestep. Hinges are toggled by the test;
NPC door interaction and actor swing protection are not implemented by this
change. No crowd, frame-time, thermal or general navigation qualification.

The original generation staging save is cloned, never edited. Source hash
remains unchanged; the user's separately changed review save is not used.
Reproduce with check_enclosed_settlement_walk.py --actor-doors --source SLOT
where SLOT is an original enclosed preparation checkpoint. The runner now
validates source identifiers and rejects incompatible check modes.
