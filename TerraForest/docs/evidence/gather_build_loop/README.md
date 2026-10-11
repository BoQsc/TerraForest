# Gather/craft/build/save/reopen check, 2026-10-11

Run `python tools/check_gather_build_loop.py` from the project. It launches two
sequential fullscreen1920x1080 cap60 processes using a new UUID save slot and new
derived cache. Both are retained; no human checkpoint is opened or modified.
Initial creation refuses an existing slot/expected record. Reopen is only launched
after creation passes. Timeout/error handling and provenance reuse the existing
check launcher. Engine/test/DLL hashes and exact arguments are retained.

In actual demo/world.tscn: clear the starter stock, gather three reachable natural
stones using the normal ground interaction coordinator, craft through the inventory
UI, place one paid brick through the construction coordinator, reject a second
unaffordable block without changes, and exercise the normal headlamp input after
closing the inventory. Save through normal verified world persistence. A separate
process verifies exact inventory and removed-ID snapshots, the spent material,
block record, and absence of gathered stones. Both phases check block scene
collision at its top face, then save and shut down normally.32 checks pass.

The initial extension of the fixture used collision layer1 (terrain); blocks use
layer2. That fixture failure is retained; final query targets layer2 and checks
the hit height. The block is placed at floor(surface height), not suspended above
terrain. Screenshots inspected. No runtime defect was found or repaired by this
work; this adds connected correctness evidence missing from separate component tests.

Limits: this is a fresh forest/terrain main world, not the furnished settlement,
and automation supplies gather rays and the block construction call. It does not
prove human aiming/navigation, ladder/door/furniture use, every recipe, travel,
mining continuity, multiplayer authority, performance or thermal sustainability.
The headlamp is the only functional use interaction covered here. M2/M3 coverage
and broader first-round gates remain open.
