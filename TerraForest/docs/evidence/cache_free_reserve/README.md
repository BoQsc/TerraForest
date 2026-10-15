# Terrain cache free-space reserve

2026-10-15, Windows, Godot 4.7.2. Optional new terrain cache packets now require
available caller disk bytes to cover the full packet plus a default 1 GiB reserve.
NativeDerivedCacheIndex.available_bytes uses GetDiskFreeSpaceExW on its leased
root and returns -1 when unowned or the query fails. The worker checks this
without traversing files. Low/unknown-space retries are throttled to two seconds.
Quota accounting and checked one-file eviction retain their separate paths.

The short cache_free_reserve test passed real native querying and writing,
simulated pressure by raising the reserve (no disk filling), non-creation of a
rejected packet, preserved readable existing packet, untouched canonical sentinel,
retry throttling, recovery, and fail-closed unknown space. The cache_eviction
regression and prepared-junction checks also passed. Both native DLL targets built.

The first junction-test invocation incorrectly used the generic launcher without
its required absolute fixture. The empty task-created directory was removed;
the fixture now rejects invalid arguments before any cache setup. The successful
run uses native Windows junctions confined to a new disposable .build directory.

This does not qualify actual disk exhaustion, simultaneous external disk writers,
filesystem metadata consumption, canonical-save space safety or endurance.
Space can change between the check and write; existing failed-write handling
remains necessary. Existing cache reads remain available. Water is unchanged.
