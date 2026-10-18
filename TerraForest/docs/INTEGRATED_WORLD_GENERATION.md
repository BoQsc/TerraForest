# Integrated world generation

The default fixed-slot launchers are now **Prepare Generated World.cmd** and
**Play Generated World.cmd**, using `generated_world_v4` with the district recipe
and profile 12. Preparation retains an existing v4 save; earlier `generated_world`,
v2 and v3 slots remain selectable in Worlds.cmd. This promotes current integrated
content, not a claim that large cities or sustained 60 FPS are qualified.

Open `Worlds.cmd`, choose the integrated regional preset, enter a name and seed,
and click **Create and play**. The browser waits for preparation and save verification
before opening the world. Existing saved worlds open directly. This local development
workflow requires Python on PATH; failures remain visible in the browser.


Create a new prepared world with a chosen seed:

```powershell
python tools/prepare_combined_world.py --layout districts --seed 42 --destination my_world_42
```

This generates profile-12 terrain, regional roads, five furnished settlement sites,
entrance paths, a western cellar, the eastern mine, four lakes and two central
patrol residents. Terrain generation and runtime representation remain native;
the preparation script coordinates existing addon authoring operations offline.
The regional topology and prefab palette are currently fixed; a different seed
changes terrain/layout parameters and central prefab choices, not the entire
settlement design vocabulary. This is not a finished procedural-city generator.

New district worlds use two mine workshops and stores at the eastern service
street, with workbenches, separate rear stores, chests, windows and entrance doors.
Existing saves keep their buildings. `Play Regional World Review.cmd` defaults to
the v6 review copy containing workshops, planted meadow paths and parked vehicles; `--review-version 3` preserves access
to the earlier cottage-based review. Both workshops have passed a saved-world player
route from their approach stairs through the doorway into the rear stores.

New district preparation also plants two 14.4-metre patches near the central and
southern sites using the accepted woodland-review species mix and curved open
path. They are dense meadow patches, not a claim of map-wide ecological coverage.
Planting uses saved native authored ground-cover records, within four existing
owner cells per patch. Surface support, structures and water exclude unsuitable
placements. Preparation now compares the complete ground-cover state on reopen.
Esc > World lists **Central meadow path** and **Southern meadow path** when their
saved planting is present; Track guides you there. Earlier saves are preserved.

Two vehicles are prepared on asphalt parking aprons just southeast of the central
and eastern road junctions (12 m east, 16 m south of each site centre). They are
ordinary persisted fleet records: approach and press E to enter, drive with the
normal controls, brake with Space, and press E when stopped to exit. Preparation
checks apron publication, collision readiness and chassis clearance, then compares
the fleet snapshot after a fresh-process reopen. No development placement is needed.
Older saved worlds are not populated retroactively.

New district worlds also stock their generated chests once during preparation:
small wood and stone supplies, plant material in housing, and a few ore pieces in
the eastern service area. These use normal native container storage and removal
protection, and their exact contents are checked on fresh-process reopen. Taking
items depletes the saved stock; opening or revisiting a world never replenishes it.
Existing saves, including generated_world_v4, retain their previous contents.

The current saved mine's main chamber and both side chambers have passed a
production-collision walking route back to the entrance. Use F or the Actions
menu for the headlamp; its beam now reaches the large chamber walls from the
centre. This does not establish mining latency or full mine-location gameplay.

The tool bakes a staging world, saves, reopens in a fresh process, compares building,
road, furnishing and resident state, and checks restored seed/generator identity.
Only a passing preparation is copied to the named destination. Existing destination
saves are never overwritten, even when a different seed is supplied. Use a new
name to generate a new world. Failures retain logs in reports/combined_preparation.
Cold preparation can take minutes; normal launches load the prepared save.

Internal preparation saves are hidden from the normal browser list. Enable
**Preparation saves (read-only)** to inspect them for recovery; they are labelled
and opened with snapshot saving disabled. The files are retained. This filter
applies only to the pipeline's exact `combined_stage_` plus 32 hexadecimal digits
identifier, not to other worlds or test saves.

Open the generated world for gameplay:

```powershell
python tools/run.py --slot my_world_42 --generator 12 --ground-cover --actors --vehicle-fleet --gameplay-construction
```

The launcher uses 1920x1080 fullscreen with a 60 FPS cap. Saved seed/generator
identity takes precedence over launch defaults. These commands do not replace the
existing regional review worlds. Esc > World lists generated destinations; travel
buttons are available only in development mode.

In normal gameplay, use **Esc > World > Track** to show the selected destination's
direction, horizontal distance and significant height difference. Tracking does
not teleport or preload the destination. Follow roads and entrances: this is a
direct bearing, not pathfinding. **Stop tracking** on the same page removes the
guide. Selection lasts for the current session and is not stored in world saves.

Supported seed range: 0 through 2147483647. Passing preparation is not a guarantee
of all-seed terrain suitability, continuous-travel performance or long-run thermal
behavior. Those require separate checks of the actual generated world.

Mixed central settlements validate both building types before placement. When a
world seed would choose only one type, a deterministic alternative building-layout
seed is recorded in the checkpoint report; the terrain seed stays unchanged.
