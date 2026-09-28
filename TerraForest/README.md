# TerraForest

## Independent building showcase

Run `python tools/run.py --scene structures --godot PATH` to inspect the separate native block construction addon. It includes textured cubes, slabs, stairs, slopes, posts and spheres; chunked native mesh baking; nearby collision; a house and tower frame; and separate static-model MultiMesh batches. See [structures API](addons/structures/README.md) and [validation](docs/STRUCTURES_VALIDATION.md). The terrain demo remains the default scene.

In the main world, press **M** for the object catalog: **1–3** selects a beam, floor panel or doorway, **R** rotates, **RMB** places and **LMB** removes a picked object. A ghost preview checks capacity and player clearance. **E** selects an existing model: arrows move it, Page Up/Down changes height, **R** rotates and **+/−** scales. Hold Shift for fine movement; **Q** returns to placement. Buttons provide the same transform actions. **Ctrl+Z** undoes model edits; **Ctrl+Y** or **Ctrl+Shift+Z** redoes them through bounded native history. **M** returns to block tools; **F5/F9** saves/reloads the combined world. See [transform editor validation](docs/MODEL_TRANSFORM_VALIDATION.md) and [model history validation](docs/MODEL_HISTORY_VALIDATION.md).

A new Godot project combining editable volumetric terrain and streamed spruce vegetation. The terrain renderer, vegetation renderer, and their integration are separate addons. The supplied TerrainRewrite and Forest12 folders are not modified.

Native development uses **Zig 0.16.0 + prebuilt godot-cpp API 4.7**. Builds compile only our extension sources. The native entity foundation and [static volumetric lake addon](addons/volumetric_water/README.md) are implemented. Roads, cities, vehicles, multiplayer and the remaining world expansion are pending. See [native development](docs/NATIVE_DEVELOPMENT.md) and the [world systems expansion contract](docs/WORLD_SYSTEMS_DESIGN.md).

## Run

Open `project.godot` with Godot **4.7.x, Windows x86-64, single precision**, or run:

```text
python tools/run.py
python tools/run.py --temporary
```

Use `--godot PATH` or `GODOT_EXE` if Godot is not on PATH. The launcher handles Steam's detached launcher by selecting its engine executable. Forward+ is the default; `--renderer mobile` selects Mobile. Compatibility is experimental and is not included in the validated renderer support claim.

The project now renders at **1920×1080 in fullscreen**, with 100% 3D scale. F11 reapplies fullscreen. Graphical benchmark reports must pass the presentation check; historical 1600×900 measurements are not 1080p evidence.

WASD moves, mouse looks, Shift sprints, Space jumps, G flies, Escape releases the mouse. Left mouse digs; right mouse builds. The wheel changes brush size; 1–3 select tools. F3 opens detailed diagnostics. The inherited controller also supports save/load and biome travel; see `demo/controller.gd` for its complete shortcuts.

**L** carves a basin at the aimed terrain and bakes static voxel water. Terrain and lake definitions now save together and restore on reopening. Use `--temporary` for disposable experiments. No swimming, flow simulation or underwater effects are implemented yet. See [world storage](docs/WORLD_STORAGE.md).

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
