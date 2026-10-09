# TerraForest

An editable volumetric terrain and streamed vegetation project for Godot, organized as modular addons. Includes native static volumetric lakes, block structures, static model placement, a native entity foundation, and compound world saves with checksums, backups and Windows file locking.

**Development integration — not a production-ready world engine.** Roads, a single vehicle, inventory/gameplay construction and street authoring have integrated implementations. Complete city generation, richer entity simulation, fleets and multiplayer remain unfinished. Performance evidence is scoped to recorded tests; large multiplayer and long-running production workloads are not certified. The [delivery plan and coverage register](TerraForest/docs/PROJECT_PLAN.md) tracks the full original scope, deferred work and completion gates.

## Start

Open [`TerraForest/project.godot`](TerraForest/project.godot) with **Godot 4.7.x on Windows x86-64, single precision**. The demo uses **1920 × 1080 fullscreen**. Included native libraries let you run without compiling.

```text
python TerraForest/tools/run.py
```

Use `--temporary` for a disposable world. WASD moves, mouse looks, Space jumps, Shift sprints, G flies, and Escape releases the mouse. Left/right mouse dig/build. L creates a basin with static water; F5 saves the world and F9 reloads it.

In the terrain world, **B** switches to independent block construction: left mouse removes, right mouse places, **1–6** select shapes, **T** changes material and **R** rotates. F5/F9 save/load terrain, water, blocks and registered static-model placements together. Building/road vegetation reconciliation and collision-readiness handling exist; dense combined worlds and sustained high-speed travel remain unqualified.

The **separate block construction showcase** contains a textured house, tower frame, stairs, slopes, fences and ladder. Its C++ structures addon stores and meshes buildings independently of terrain, with a separate spatial MultiMesh path for static models:

```text
python TerraForest/tools/run.py --scene structures
```

See the [structures API and limitations](TerraForest/addons/structures/README.md) and [validation evidence](TerraForest/docs/STRUCTURES_VALIDATION.md). This is a building foundation; city streaming, LOD and multiplayer are still pending.

## Documentation

- [Project guide and addon layout](TerraForest/README.md)
- [Delivery plan, coverage gates and deferred work](TerraForest/docs/PROJECT_PLAN.md)
- [Delivered features and remaining work](TerraForest/docs/DELIVERY_STATUS.md)
- [Architecture](TerraForest/docs/ARCHITECTURE.md)
- [Native development with Zig and prebuilt godot-cpp](TerraForest/docs/NATIVE_DEVELOPMENT.md)
- [World storage and recovery](TerraForest/docs/WORLD_STORAGE.md)
- [Storage validation evidence](TerraForest/docs/STORAGE_VALIDATION.md)
- [Water validation evidence](TerraForest/docs/WATER_VALIDATION.md)

The project folder contains the addons, demo, native source, tools and validation evidence. Generated editor caches, local reports and distribution archives are excluded from Git. Run the packaging tools described in the project guide to create distributable archives.

## License

Project code uses [Zero-Clause BSD](LICENSE.txt). Third-party assets and dependencies retain their own licenses; see the notices included with each addon.
