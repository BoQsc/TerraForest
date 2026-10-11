> Architecture cleanup: static-lake and basin-network implementations are removed from source and registration. NativeRegionalWater is the only water owner; NativeWaterTerrainPatch samples terrain on its worker. NativeLakeCatalog only encodes metadata and reads older saves. Historical evidence is not an alternate supported runtime. Shoreline reconstruction remains unfinished; nearest-surface depth transmission resolves overlapping-face tinting; stepped shores still fail visual acceptance; this cleanup does not establish visual quality or sustained 60 FPS.

# Regional water in the playable world

The normal world now uses `NativeRegionalWater` for editable water. The earlier fixed-basin network is retained as native reference code, not the gameplay water owner. Terrain edits are no longer blocked around filled lakes.

Run **Play Water Gameplay.cmd** for the saved `water_gameplay_v2` world (the old `water_gameplay` save is retained). **Prepare Water World.cmd** optionally prepares and saves its spawn area headlessly before graphical play. It uses the same game scene, terrain worker, generator and save path; it is not a separate showcase. The preparation command does not bake an unbounded entire world. Existing saved terrain takes precedence over generator arguments.

- A bucket holds 10 litres. Left mouse scoops one litre; right mouse pours one litre, including into a newly dug hole outside any authored lake.
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
