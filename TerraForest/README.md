# TerraForest

See the [delivery plan and coverage register](docs/PROJECT_PLAN.md) for current milestones, original-scope gaps and explicit return points for deferred work. Historical validation documents describe their recorded builds, not completion of the whole project.

## Playable checkpoints

Open `Worlds.cmd` (or run the project from Godot) for the world browser. Select a
saved world, or create a named world with a landscape preset and seed. Save from
the Actions menu or F5 to retain a new world. Gameplay material costs can be
enabled or disabled before opening. Initial terrain loading still takes time;
this screen does not pre-bake an entire world.
Use **Esc > Session > World browser** to save and choose another world.

| Launcher | What to try |
| --- | --- |
| `Play Combined Gameplay.cmd` | Resource gathering, crafting, construction and chest storage. |
| `Review Mixed Neighborhood.cmd` | Five cottages and three furnished towers, connected streets, doors and windows. |
| `Play Natural Caves.cmd` | Persistent cave exploration and ordinary pickaxe mining from a saved entrance. |

Each uses its own save slot. Preparation preserves existing progress; F5 saves.
First-time world preparation can take longer than later launches. See the
[building guide](docs/BUILDING_REVIEW.md), [cave guide](docs/NATURAL_CAVE_GAMEPLAY.md)
and [player UI guide](docs/PLAYER_UI.md). These are partial gameplay checkpoints;
sustained 60 FPS, dense cities, large active populations and multiplayer remain
unqualified or unfinished.

## Independent building showcase

Run `python tools/run.py --scene structures --godot PATH` to inspect the separate native block construction addon. It includes textured cubes, slabs, stairs, slopes, posts and spheres; chunked native mesh baking; nearby collision; a house and tower frame; and separate static-model MultiMesh batches. See [structures API](addons/structures/README.md) and [validation](docs/STRUCTURES_VALIDATION.md). The project opens the world browser; `tools/run.py` still defaults to the terrain demo for existing launchers.

In the main world, open **Esc → Objects** for object recipes and placement
controls, or **Esc → Building** for block shapes and prefabs. Gameplay uses owned
tools and materials. **~** switches to the separate development toolbelt and
editor controls, including transforms and history. M/B mode switching is no
longer the normal interaction path. See the [player UI guide](docs/PLAYER_UI.md)
for current controls; older transform validation reports describe their tested
builds rather than today's keyboard layout.

A new Godot project combining editable volumetric terrain and streamed spruce vegetation. The terrain renderer, vegetation renderer, and their integration are separate addons. The supplied TerrainRewrite and Forest12 folders are not modified.

Native development uses **Zig 0.16.0 + prebuilt godot-cpp API 4.7**. Builds compile only our extension sources. Implemented paths include native entity storage/kinematics, [static volumetric lakes](addons/volumetric_water/README.md), seeded cave/mountain/geology generation, terrain road editing, block/prefab construction and a [single world vehicle](addons/vehicle_runtime/README.md). Native [connected settlement authoring](docs/CONNECTED_SETTLEMENTS.md) now supports multiple streets. Multiplayer, vehicle fleets, automatic terrain-aware settlement placement and qualification of dense populated worlds remain incomplete. See [native development](docs/NATIVE_DEVELOPMENT.md), [delivery evidence and limitations](docs/DELIVERY_STATUS.md), and the [world systems expansion contract](docs/WORLD_SYSTEMS_DESIGN.md).

In development mode, **Esc > Development > Place vehicle** places a vehicle on nearby clear, loaded ground. **E** enters or exits when stopped. **W/S** accelerates, brakes or reverses; **A/D** steers; **Space** applies the handbrake; **Shift** boosts; **R** resets. **F5** saves while seated when a clear on-foot restore location exists beside the vehicle. Reload restores you on foot beside the parked vehicle; momentum and cosmetic dents are not saved. The isolated `Launch Vehicle Demo.cmd` runs the supplied driving scene separately. Graphical checks use 1920×1080 fullscreen with a 60 FPS cap; this is a test configuration, not a sustained performance guarantee.

## Run

Open `project.godot` with Godot **4.7.x, Windows x86-64, single precision**, or run:

```text
python tools/run.py
python tools/run.py --temporary
```

Use `--godot PATH` or `GODOT_EXE` if Godot is not on PATH. The launcher handles Steam's detached launcher by selecting its engine executable. Forward+ is the default; `--renderer mobile` selects Mobile. Compatibility is experimental and is not included in the validated renderer support claim.

The project now renders at **1920×1080 in fullscreen**, with 100% 3D scale. F11 reapplies fullscreen. Graphical benchmark reports must pass the presentation check; historical 1600×900 measurements are not 1080p evidence.

WASD moves, mouse looks, Shift sprints and Space jumps. **Esc** opens Actions;
**Tab** opens inventory. **1–9 / 0** or the mouse wheel selects any of the ten
toolbelt slots, including empty slots. Left mouse attacks/digs with the equipped
tool or empty hands; right mouse uses placeable items or the selected building
recipe. **E** interacts and **G** drops one held item in gameplay. **~** switches
development mode; flight is available in its menu. **F** toggles the headlamp.

The development menu offers **Carve lake at aim**. Ordinary gameplay uses the
water bucket: one click collects or places one whole water unit. Water stays
where placed; flow/spillage is deferred. Terrain and water save together. Use
`--temporary` for disposable experiments. See [water gameplay](docs/WATER_GAMEPLAY.md)
and [world storage](docs/WORLD_STORAGE.md).

Automatic model region paging is available for integration qualification with
`python tools/run.py --slot model_paging_trial --model-region-paging`. It remains
opt-in; the default/human-checkpoint path is unchanged. See the
[lifecycle contract and evidence](docs/MODEL_PAGING_LIFECYCLE.md) before interpreting
this as dense-world performance support.

## Addons

| Folder | Responsibility | Dependencies |
| --- | --- | --- |
| `addons/volumetric_terrain` | Native density world, editing, meshing, collision, LOD, persistence | Godot and included platform native library |
| `addons/vegetation` | Cell MultiMeshes, source/proxy LOD, transitions, shadows, wind | Godot and included spruce assets |
| `addons/world_ecosystem` | Deterministic placement, bounded residency, edit invalidation | Both addons above |
| `demo` | Player, editing controls, lighting and HUD | The three addons |
| `addons/world_runtime` | Native entity pool, bulk transforms, versioned compound snapshots and atomic Windows publication | Windows x86-64, Godot 4.7 single precision |
| `addons/presentation` | Startup fullscreen policy and measurement metadata | Godot |
| `addons/volumetric_water` | Native connected basin occupancy, depth queries, surface extraction; optional terrain adapter | Windows x86-64; terrain adapter requires volumetric_terrain |

Copy an addon directory into another project. Enable its editor plugin when supplied; `world_runtime` loads through its GDExtension descriptor and `presentation` is a support library. Runtime scripts also work without enabling editor plugins. The core addons do not import each other or anything from `demo`. Do not copy `.godot` between projects. See each addon's README and [architecture](docs/ARCHITECTURE.md).

## What changed

- Actual terrain density support replaces the forest's unrelated benchmark heightfield.
- Stable deterministic placement streams in nearest cells first, with at most two surface batches outstanding. Edits win worker admission.
- Revision/epoch checks prevent asynchronous work from repopulating stale terrain. Edited columns stay excluded after save/load.
- Explicit resident-cell and root budgets constrain forest growth during travel. Removing cells releases ownership, render batches, and selector state.
- Terrain frame budgets are Inspector properties. Public edits validate complete command groups before mutation; save slots are isolated under `user://worlds`.
- Existing native meshing, atomic collision publication, compact foliage maps, fitted view proxies and incremental LOD work are retained.
- Raw asset loading works from exported packs; obsolete 55 MB comparison textures are excluded.
- A new scene supplies a sky, atmosphere, vegetation lighting, smooth biome material transitions and a compact HUD.

## Verify and package

```text
python tools/audit_paths.py
python tools/build_native.py --target all
python tools/validate.py --test native_runtime
python tools/test_native_release.py
python tools/validate.py --test world_archive
python tools/validate.py --test world_persistence
python tools/test_native_release.py --test world_archive
python tools/test_native_release.py --test world_persistence
python tools/test_archive_process.py
python tools/validate.py --test water
python tools/test_native_release.py --addon volumetric_water
python tools/validate.py --test water_integration --gpu
python tools/validate.py --test presentation --gpu
python tools/validate.py
python tools/validate.py --gpu
python tools/validate.py --test persistence
python tools/test_isolation.py
python tools/soak.py --cycles 20 --uncapped
python tools/export_pack.py
python tools/package.py
python tools/verify_package.py
```

Reports are written to `reports/`; source archives and resource packs to `dist/`. The source archive excludes editor caches, temporary builds and test output. The resource-pack export does not require executable export templates; keep the accompanying `dist/addons` native-library folder beside the PCK. A standalone `.exe` export requires templates matching the installed Godot version.

## Scope and readiness

This is a tested integration and architecture revision, **not a certification of production readiness or a measured speedup over both original projects**. Read [water validation](docs/WATER_VALIDATION.md), [native/1080p validation](docs/TOOLCHAIN_VALIDATION.md) and [historical integration validation](docs/VALIDATION.md) for measured results and remaining release gates.

[Delivery status](docs/DELIVERY_STATUS.md) retains the full requested scope and the evidence still needed. [Storage validation](docs/STORAGE_VALIDATION.md) records the latest compound-save and recovery tests.

The native world remains approximately 2 km × 2 km × 256 m, seed 1703. One active terrain world per process is enforced because native cancellation is global. Terrain nodes require an identity world transform. The supplied vegetation asset is one spruce species. Trees currently have visual/shadow geometry, not gameplay collision. Procedural trees are conservatively excluded from edited 16 m columns rather than regrown on arbitrary new surfaces or cave ceilings. Multi-hour endurance, network replication, consoles, macOS/ARM, arbitrary world sizes and arbitrary species are outside the validated scope.

Code is 0BSD. Supplied spruce derivatives retain the source's stated CC0 terms. See `LICENSE.txt`, addon licenses, `ASSET_LICENSE.md`, terrain texture notices and [provenance](docs/PROVENANCE.md).

## Addon dependency bundles

Run `python tools/package.py --addon vehicle_runtime` (or another addon name) to create only that ZIP under `dist`. With no option, the tool creates the source archive and all ten addon bundles, including player and vehicle runtimes. Extract a bundle into the destination project root, preserving its paths. Review existing files before merging into another project. Each archive includes its own SHA-256 manifest; addon archives also include `ADDON_PACKAGE.json` describing the included addons and binary support. Project and bundled dependency/asset license notices are retained.

Bundles include declared dependencies: terrain includes world runtime and water; structures includes terrain and its dependencies; vegetation includes native vegetation runtime; world ecosystem includes vegetation, terrain and their dependencies. The vehicle bundle includes `vehicle_demo` source assets, scripts and provenance. World runtime includes player runtime and water for its dropped-item adapter; player runtime includes water for bucket item support. Structures also includes player runtime. Presentation, vegetation runtime, and vehicle runtime have no other addon-directory dependencies. These are file dependency bundles, not a claim that every adapter is an independently configured scene: host callbacks and world services still follow each addon's documented API.

Prebuilt binaries support Godot 4.7 Windows x86-64 single precision. Other platforms are unqualified and require compatible builds. `python tools/test_package.py` checks deterministic archives, local manifests, cache exclusion and existing literal resource references for every declared bundle. Constructed resource paths and runtime host contracts need separate tests. The vehicle bundle has additionally passed clean-project asset import and native scene instantiation; full driving/rendering and all-addon clean-install qualification remain open. Evidence: `docs/evidence/addon_packaging`.

Clean bundle verification: after packaging, run `python tools/verify_addon_bundle.py --addon world_runtime --godot PATH_TO_GODOT`. It checks exact archive membership/hashes, extracts into a cache-free temporary project, imports, and loads scripts/scenes/resources. Logs and exit codes go to `reports/addon_bundles/<addon>`. A failed import remains a failure even if subsequent loading succeeds. This does not enable editor plugins or exercise host-world behavior.

The 2026-10-10 clean-import matrix is **not fully passing**. Presentation, structures, world ecosystem and vehicle bundles pass import/resource loading. Player runtime, world runtime, native vegetation runtime, water, terrain and vegetation bundles terminate their editor import with `0xC0000005` on Godot 4.7.2 Windows. A world-runtime follow-up reproduces that failure while subsequent ordinary script loading passes. The common engine fault location does not establish root cause. These bundles must not be advertised as qualified standalone installs until the import failure is resolved. Evidence: `docs/evidence/addon_bundle_matrix`.

Import mitigation (2026-10-10): all six previously failing bundles pass with `--import-frame-delay-ms 1000` added to the verifier command. This passes Godot's `--frame-delay 1000` to the editor import process only; ordinary resource loading and game launch remain unchanged. Workaround reports use a separate `delay_1000` subdirectory, preserving default-run evidence. The verifier now also checks that packaged GDExtensions are actually loaded.

The minimal native-only crash and delay-dependent success are consistent with the [upstream GDExtension documentation cleanup race](https://github.com/godotengine/godot/issues/111048), but no local symbolized stack establishes exact attribution. The ordinary immediate-import failures remain open. A fixed delay is a tested automation mitigation, not an engine fix or a guarantee across machines. Evidence: `docs/evidence/addon_import_workaround`.

For an actual standalone actor navigation check after packaging world_runtime, add `--exercise-actors` to `tools/verify_addon_bundle.py --addon world_runtime --godot <engine> --import-frame-delay-ms 1000`. This runs the existing two-actor obstacle fixture inside the extracted bundle at fullscreen 1920x1080/cap60, with no main-project runtime resource fallback. It qualifies this adapter path only, not population performance or all bundled adapters.

Dropped-item bundle validation: `--exercise-pickups` on the world_runtime verifier checks all 23 models, native inventory transfers, occlusion rejection and exact in-memory compound restoration in the extracted project. Player-runtime bundles include the shared building texture assets and woodland shader referenced by baked drop meshes, without pulling in those entire runtime addons. `ADDON_PACKAGE.json` lists these under `asset_paths`. The verifier also loads binary `.res` resources to catch their embedded dependencies.

Saved-world terrain preparation: run `Prepare World Cache.cmd --slot combined_gameplay` before playing (or name another existing slot). It loads the saved world read-only and populates the normal derived terrain cache around the saved spawn and ordinary coverage. Add `--verify` for a second, fullscreen1080p process that verifies cache hits; reports retain counters and the unchanged canonical-save hash. Optional `--cache user://my_cache` isolates a test cache; normal play must use the same `--derived-cache=user://my_cache` to reuse it. This is not an entire-world bake, does not regenerate or overwrite a save, and does not remove runtime mesh upload/collision costs. Close that world first so preparation can acquire its existing save lease.

Settlement driving checkpoint: **Review Settlement Road.cmd** opens a separate saved settlement with a 112 m terrain-following road extension and parked vehicle. First preparation uses a copy of `combined_gameplay` and requires a successful drive/reopen check. See [coverage and limitations](docs/SETTLEMENT_ROAD_TRIP.md).
