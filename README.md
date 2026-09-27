# TerraForest

An editable volumetric terrain and streamed vegetation project for Godot, organized as modular addons. Includes native static volumetric lakes, a native entity foundation, and compound terrain/water saves with checksums, backups and Windows file locking.

**Development integration — not a production-ready world engine.** Roads, cities, vehicles, complete inventory and multiplayer are pending. Performance evidence is scoped to the tests documented below; large multiplayer and long-running production workloads are not certified.

## Start

Open [`TerraForest/project.godot`](TerraForest/project.godot) with **Godot 4.7.x on Windows x86-64, single precision**. The demo uses **1920 × 1080 fullscreen**. Included native libraries let you run without compiling.

```text
python TerraForest/tools/run.py
```

Use `--temporary` for a disposable world. WASD moves, mouse looks, Space jumps, Shift sprints, G flies, and Escape releases the mouse. Left/right mouse dig/build. L creates a basin with static water; F5 saves the world and F9 reloads it.

## Documentation

- [Project guide and addon layout](TerraForest/README.md)
- [Delivered features and remaining work](TerraForest/docs/DELIVERY_STATUS.md)
- [Architecture](TerraForest/docs/ARCHITECTURE.md)
- [Native development with Zig and prebuilt godot-cpp](TerraForest/docs/NATIVE_DEVELOPMENT.md)
- [World storage and recovery](TerraForest/docs/WORLD_STORAGE.md)
- [Storage validation evidence](TerraForest/docs/STORAGE_VALIDATION.md)
- [Water validation evidence](TerraForest/docs/WATER_VALIDATION.md)

The project folder contains the addons, demo, native source, tools and validation evidence. Generated editor caches, local reports and distribution archives are excluded from Git. Run the packaging tools described in the project guide to create distributable archives.

## License

Project code uses [Zero-Clause BSD](LICENSE.txt). Third-party assets and dependencies retain their own licenses; see the notices included with each addon.
