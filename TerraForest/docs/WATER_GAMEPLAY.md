> Open visual/correctness failure, 2026-10-13: `python tools/check_regional_water_world.py --contact-only` reproduces a 12.5 cm gap between poured-water cell floors and terrain in about 13 seconds. The 10 L amount is conserved, but the existing conservative occupancy leaves a thin layer floating above the actual ground. This must be corrected before water visual acceptance. See `evidence/water_puddle_contact/status.txt`.

> Bucket interaction review: run `Review Water Buckets.cmd` for a disposable normal world with the bucket selected and water within reach. Left click fills up to 10 L; right click pours all contents. Turn toward dry terrain to compare poured and scooped water. Changes are discarded on close. This is visual review, not final water acceptance.

> Connected-lake evidence, 2026-10-13: a local removal in a 256-region flat lake rebuilt eight packets and settled in two simulated frames. Repeated edits crossing region boundaries produced up to seven-frame publication batches. This is a headless native test, not measured graphical latency. See `evidence/water_connected_scaling/status.txt`. Sustained-edit publication delay remains open.

> Snapshot scope update, 2026-10-13: copy-on-write now retains only data inside the active batch reconstruction/readiness halo. A targeted test performs 255 distant edits with zero copied regional payload while preserving local snapshot consistency. See `evidence/water_snapshot_scope/status.txt`. This does not bound a large connected batch.

> Local publication update, 2026-10-13: independent dirty water areas publish separately; adjacent owners remain coherent. Brush/bucket edits and completed terrain patches receive queue priority after the current batch. The 256 isolated-pool fixture now publishes its first pool after three packets, rather than waiting for 768. Total loading work is unchanged, and large connected batches remain a latency limit. See `evidence/water_local_publication/status.txt`.

> Restore scaling check, 2026-10-13: unnecessary empty publication work is removed. At 256 synthetic isolated regions, packets fell from 6912 to 768, but the four-packet limit still implies at least 3.2 seconds to publish that batch at 60 FPS. Local interior edits rebuilt one region at all tested sizes. See `evidence/water_publication_scale/status.txt` for scope and raw evidence. Large-batch latency remains open.

> Work in progress, 2026-10-13: runtime water geometry now uses the terrain surface-nets crossing aggregation, connectivity and triangulation. Exact wet-interval crossings keep litre-scale layers representable. The old custom top/side/shore geometry assembly is removed from `next_mesh`. Stored finite water quantities and flow are unchanged. Bucket raycasts and nearest-surface queries now use the same triangle builder as rendering; the old shoreline geometry is removed. Physical depth uses authoritative wet intervals. Gameplay queries retain the exact published triangle snapshot and switch only when the scene acknowledges the rendered batch. Transfers still validate current water quantities, and invalid terrain occupancy remains temporarily unpickable. Water rendering now stages immutable batches and swaps each complete batch in one frame. Snapshot copies are taken lazily before mutable region access; terrain invalidation cancels staged work. Large-scale batch latency, staging memory and sustained laptop performance remain unqualified. Earlier validation below describes earlier implementations and is not acceptance of this replacement. The continuity checks now verify closed components instead of old quad coordinates: diagonal pools and solid ledges remain separate, including all 510 shallow/full occupancy patterns in a 2x2x2 group. This resolves those reproduced topology defects, not arbitrary-world correctness.

> Historical cache note: format 2 retains terrain corner samples. Version 1 upgrades those derived samples once through the terrain worker. The shoreline-clipping evidence describes an earlier implementation, not the current shared mesher.

> Architecture cleanup: static-lake and basin-network implementations are removed from source and registration. NativeRegionalWater is the only water owner; NativeWaterTerrainPatch samples terrain on its worker. NativeLakeCatalog only encodes metadata and reads older saves. Historical evidence is not an alternate supported runtime. Shoreline reconstruction remains unfinished; nearest-surface depth transmission resolves overlapping-face tinting; stepped shores still fail visual acceptance; this cleanup does not establish visual quality or sustained 60 FPS.

# Regional water in the playable world

The normal world now uses `NativeRegionalWater` for editable water. The earlier fixed-basin and static-lake runtimes have been removed. Terrain edits are no longer blocked around filled lakes.

Run **Play Water Gameplay.cmd** for the saved `water_gameplay_v2` world (the old `water_gameplay` save is retained). **Prepare Water World.cmd** optionally prepares and saves its spawn area headlessly before graphical play. It uses the same game scene, terrain worker, generator and save path; it is not a separate showcase. The preparation command does not bake an unbounded entire world. Existing saved terrain takes precedence over generator arguments.

- A bucket holds 10 litres, stored in whole-litre units. Scooping a smaller puddle takes available whole litres and leaves any fractional remainder in the world. One left click fills available bucket capacity; one right click pours all contents, including into a newly dug hole outside any authored lake.
- Water moves into newly mined openings and down through unsupported space. It retains finite quantities instead of refilling to an authored level.
- Esc > Development > Water offers water addition and a local removal brush. Removing water does not remove terrain.
- Normal Save / F5 stores terrain, water and bucket inventory together. Chest transfers, drops and inventory moves retain the bucket's fill-state item.
- The dedicated starter lake is a shallow elongated excavation, filled near its bank. It no longer uses the previous deep 12 m sphere. Existing lake geometry is preserved.

## Runtime ownership and cost

C++ owns sparse 0.5 m water cells, grouped into 4 m regions. Quantities are integer millilitres. Gravity and local head equalisation operate on an active-cell queue; resting cells leave that queue. A 1 mm head tolerance prevents sub-millimetre differences from keeping large areas awake. This is a conservative cellular liquid model, not a velocity/pressure or Navier–Stokes solver.

The terrain worker supplies immutable regional occupancy patches through bounded native interpolated-density batches. The live water store is never shared with that worker. Mining invalidates only intersecting cached regions; water in those regions waits for the new terrain samples, retaining its quantity. Terrain additions that displace water keep any temporarily trapped excess rather than deleting it.

Simulation has a soft 1 ms main-thread slice and an operation cap. Presentation has a shared soft 1 ms target and at most four small regional mesh uploads per frame. These are cooperative targets, not hard real-time guarantees. Water has no per-cell scene nodes, scripts or physics bodies. Opaque surfaces share one shader and cast no shadows. Dirty meshes coalesce while flow continues; quantities update before their surface can be republished.

Aiming tests the water surface analytically so a thin puddle is not missed between ray samples. Scooping can collect a litre across locally connected wet cells. Pouring against a conservative terrain boundary selects open space immediately back along the unobstructed aiming segment. A cold regional request retains the bucket until sampling and inventory revision validation succeed; stale actions cannot consume or create water.

## Saving and cached loading

The versioned regional snapshot stores authoritative amounts and awake flags, plus cached terrain floor/ceiling intervals. Cache validity belongs to the terrain in the **same compound world snapshot**. An accepted edit invalidates the affected cache before a save can capture it. Invalid or still-pending regions remain marked for sampling after reopen; valid cached regions are restored without density sampling or basin-network compilation.

The normal archive supplies checksums and atomic publication. The native water decoder validates format, bounds, unique ordered region keys and exact quantity totals before swapping live state. Derived occupancy algorithm changes require a format/version migration, not blind reuse of an old cache. Surface meshes are reconstructed from cached regional data under the presentation budget; GPU objects are not serialized.

Loading publishes restored water surfaces before giving the player control, and does not advance the restored flow while the loading screen is up. A saved region that had not finished preparation may still require sampling. Telemetry distinguishes cache hits, cached-region rebuilds, sampled nodes and pending regions; newly explored flow regions must not be mistaken for failed cache reuse.

Legacy lake definitions are accepted. Legacy finite saves import their recorded total quantity into the new regional representation instead of refilling them. Exact old basin leaf assignments and shore geometry are not preserved by this representation change. Any excess that cannot initially fit remains owned at the seed and redistributes; original terrain is unchanged. Normal archive recovery retains the preceding checkpoint.

## Scope and limits

- 0.5 m cells and conservative terrain intervals give approximate shorelines and cannot resolve sub-cell passages. Surface edges can still look stepped. Visual refinement is open.
- The solid field currently follows volumetric terrain, not separate building or vehicle collision shapes. Constructed dams require structure-to-water occupancy integration.
- Water is bounded by the current terrain domain. The resident store has a 4,096-region ceiling; at that ceiling expansion pauses and quantities are retained. Wet-region disk paging, large oceans and long-range pressure transport are not implemented.
- The preparation launcher prepares the spawn area and the water it generates. It is not a complete regional world compiler, nor proof of instant travel at arbitrary speeds.
- Conservation and the tested local gameplay loop do not establish sustained 60 FPS, laptop thermal sustainability, large multiplayer performance or unlimited scale.

## Reproduction

`python tools/check_regional_water_world.py` runs a short fullscreen 1920×1080 actual-world check in a unique real save slot and isolated terrain cache. It exercises real bucket mouse events, an independent dug hole and recoverable litre puddle, a mined lake outlet, exact conservation, developer removal, ordinary save and a new game instance reopening the disk archive. It checks cached-region reuse, invalid-snapshot rejection and zero flow steps for the undisturbed sleeping lake. It records frame intervals, viewport CPU/GPU rendering times, native work counters and a screenshot. Headless execution cannot validate captured mouse input and is not the acceptance run.

`python tools/prepare_water_world.py --slot <name>` prepares a separate saved spawn area. Use the same slot with `python tools/run.py --slot <name> --water-gameplay --gameplay-construction` to play it. `--dry-run` shows the command without changing a world.

Project water code and original bucket assets remain 0BSD. Builds continue to use pinned Zig and prebuilt godot-cpp.
