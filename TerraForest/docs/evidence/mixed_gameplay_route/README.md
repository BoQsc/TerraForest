# Mixed neighborhood gameplay route — 2026-10-15

Source: original generated staging save
`combined_stage_7801173ed84740ee91a1b06e51a3298b`, not the mutable human review.
Each run clones it exclusively and verifies the source canonical hash is unchanged.
All processes use 1920×1080 fullscreen, full render scale, cap 60.

The resource phase gathers five actual natural stones through E interaction,
crafts one brick from two earned stones using the inventory crafting button,
moves it to the toolbelt and places it with right click. It deposits two stones
in an existing cottage chest, withdraws one and saves. The test relocates the
player between gathering and storage; it does not establish continuous exploration.

The next process walks from that saved chest through the door and down the stairs,
places/enters a vehicle on the authored street, drives 12 m, brakes, reverses,
exits and walks back inside. A third process verifies exact inventory, chest,
gathered identities, paid brick and door-state persistence. No free resource
grants or vehicle pose correction are used. This covers one cottage/short street
route among the mixed buildings, not all interiors or road-region crossings.

Results:
- 20261015T175823950861Z: resource phase passed; reverse-return failed with
  12.06 m remaining position error. Later walking and inventory checks passed.
- 20261015T180126586880Z: all three processes passed; return error 2.55 m
  (the existing gate is <3 m). Total phase durations 12.31 / 27.47 / 12.02 s.
- 20261015T180253034571Z: all three processes passed with half-second reverse
  samples. Input remained active, four wheels loaded, no freeze/readiness hold.

The first failure has no sufficient telemetry to assign a cause. No production
vehicle fix is claimed. The fixture now retains input, support, drive speed,
sleep/freeze and streaming state, bounded by its existing ten-second reverse
deadline. Stop repeating this route without new evidence; return to the failure
when it recurs or at vehicle qualification. Passing reruns do not erase it.

Terrain receive hitches around 132 ms remain in logs. No frame-tail, thermal,
high-speed or long-session qualification is implied. Water remains deferred.
