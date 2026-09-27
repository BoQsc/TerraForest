# Native development: Zig and prebuilt godot-cpp

The native toolchain is pinned in `native_toolchain.lock.json`:

- Zig 0.16.0, Windows x86-64, downloaded from ziglang.org.
- BoQsc/godot-cpp-prebuilt release `api-4.7-d7b6162-zig`, upstream commit `d7b6162249ed52796a8301d216c24ee71d68c2bf`.
- Godot API 4.7, **single precision**, target `x86_64-windows-gnu`.
- Both `template_debug` and `template_release` static libraries are supplied by that release.

```text
python tools/bootstrap_native.py
python tools/build_native.py --target all
python tools/validate.py --test native_runtime
```

The bootstrap verifies download length and SHA-256 **before extraction or execution**. Existing matching Zig on PATH or at `ZIG_EXECUTABLE` is reusable. Otherwise the default cache is `%LOCALAPPDATA%/TerraForest/toolchains`; `TERRAFOREST_TOOLCHAINS` overrides it. No machine-wide PATH modification, administrator install, SCons installation or local godot-cpp build is required.

The build validates `BUILD_INFO.json`, compiles our `world_runtime` and `volumetric_water` native sources, and links each addon against the matching prebuilt archive. Use `--addon world_runtime` or `--addon volumetric_water` to select one; the default builds both. Object files and Zig caches are retained; unchanged input produces no C++ recompilation or relink. Local headers, flags, pinned SDK identity and archive content participate in the build signature. A first Zig link may build Zig's own C/C++ runtime cache; that is distinct from rebuilding godot-cpp.

Stop processes that have the DLL loaded before rebuilding it. Output publication uses a completed temporary DLL; a failed build does not overwrite the previous one. Hot reload is disabled. The C++ addon uses Godot's official bindings from the downloaded package; the prebuilt distribution itself is community-maintained. Its MIT license accompanies our linked addon.

The existing raw-C-ABI terrain addon remains unchanged by this toolchain setup. The new `world_runtime` addon is the typed C++ foundation for additional systems. Migration must preserve save formats, cache signatures, collision publication and thread ownership; merely recompiling does not make the existing GDScript terrain/forest schedulers native.

## Current native surface

`NativeEntityStore` is a bounded, dense entity pool with stable generation-checked handles, batch creation, native kinematic updates and bulk MultiMesh transform output. It creates no per-entity scene nodes. Mutations belong to one simulation thread; concurrent access is not supported. Handles are local to one store. Pool memory is capped at 262,144 entities; invalid inputs and capacity exhaustion return failure without partial mutation.

This foundation intentionally does not claim collision resolution, vehicle dynamics, gameplay AI, network replication, or a complete multiplayer entity system. Those require explicit integration and separate tests.

## Upgrade policy

Update the lock to a matching published SDK/toolchain pair, review its ABI metadata, download it once, rebuild only our extension, and run the real-engine tests. Single/double precision, compiler ABI and platform archives are not interchangeable. The supplied release is Windows-only; other platforms need matching prebuilt releases before we claim support.
