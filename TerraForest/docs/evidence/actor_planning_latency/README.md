# Bounded actor planning latency and destination reload

2026-10-11. Baseline c0979a6 plus the recorded working-tree change. Run manifests
retain engine/binary hashes and presentation settings. Both native targets built;
checks use the debug extension. This is not whole-world performance qualification.

## Failure and change

Sixteen simultaneous unobstructed six-metre routes took 2.22–2.23 simulated seconds
to become usable, failing the one-second gate. The store also held 1,000 distant
sleeping actors. All sixteen eventually arrived; the failure was planning delay.

The native planner now checks a direct corridor in <=0.5 m increments, using the
same support rays, capsule sweeps, readiness and admission checks as A*. Each
segment consumes one existing shared work unit. Any failed segment discards that
candidate and falls back to A* from the original start. All tested bounds remain
part of edit invalidation. The +/-16 m local limit bounds a direct candidate to
at most 46 segments; no route data is persisted.

## Results

- Clear-route readiness: 0.267–0.283 seconds; all sixteen arrived within six seconds.
- Shared work peak: 12, unchanged; exactly 16 physics proxies, 1,000 records asleep.
- Planning peak: 780 microseconds. The 750 us deadline remains cooperative.
- Actor adapter peak: 8.04 ms in this short headless run. This is still substantial
  and is not a total-frame, sustained CPU, GPU, crowd or older-laptop guarantee.
- Existing route contract: 14 checks pass, including wall detours, edits, sealed
  areas, unavailable collision, departure/return and bounded work/storage.
- Actual cottage: six checks pass at fullscreen 1920x1080/cap60; entrance image
  inspected and shows the actor inside the unchanged doorway. No FPS gate asserted.
- Actor-component disk reload: seven checks pass. A moving actor retains exact
  saved position and destination, retires old proxies/handles, and a newly created
  component replans and arrives. Uses native archive publication and production
  provider ordering, with a fixture terrain payload. This does not test full terrain
  save orchestration, a separate process, or the furnished main-world route.

The initial reload fixture used a StringName terrain key through dot assignment;
native archives require String keys. Its retained failure was fixed in the fixture
with bracket notation; production archive code did not change.

Next: a furnished-settlement route and integrated saved-order continuation. Crowd
avoidance, regional routing, shared route caching and population/frame qualification
remain open. Player stair evidence remains in ../actor_cottage_navigation.
