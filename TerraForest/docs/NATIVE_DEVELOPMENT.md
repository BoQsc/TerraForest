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

The bootstrap verifies download length and SHA-256 **before extraction or execution**. Existing matching Zig on PATH or at `ZIG_EXECUTABLE` is reusable. Otherwise the default cache is `%LOCALAPPDATA%/TerraForest/toolchains`; `TERRAFOREST_TOOLCHAINS` overrides it. No machine-wide PATH modification, administrator install or SCons installation is required. One binding translation unit is rebuilt for the lifetime repair below; the rest remains prebuilt.

The build validates `BUILD_INFO.json` and builds all seven native addon families by default; use `--addon` to select one. Each links the repaired Dictionary object before the matching prebuilt archive. Object files and Zig caches are retained; unchanged input produces no C++ recompilation or relink. Local `.h`/`.hpp` headers, flags, pinned SDK identity, archive content and repaired binding object participate in the build signature. A first Zig link may build Zig's own C/C++ runtime cache.

### Pinned Dictionary lifetime repair — 2026-11-09

The supplied SDK's Dictionary move assignment overwrites a live reference without
releasing it. Erasing an interior archive-completion queue entry reproduced **48
surviving survey wrappers out of 80**; ordinary in-order consumption concealed it.
The same test releases all 80 after the repair. This affects other native
Dictionary assignments too, so all fourteen debug/release addon DLLs use the fix.

`tools/build_native.py` verifies the exact SDK `gen/src/variant/dictionary.cpp`
SHA-256 `cbeecb1484782dc2896a57061e52d7d2c0d4a90f6db2e27186b5eb7aab7f4ecd`,
then creates a derived file under `.build/native/bindings` with its original MIT
copyright/license header intact. Only move assignment changes, to swap ownership.
This matches the behavior of [upstream repair #2055](https://github.com/godotengine/godot-cpp/pull/2055).
The original SDK cache and dependency version remain unchanged. The complete
Dictionary object resolves before archive extraction, excluding the defective
prebuilt object; no duplicate symbol suppression is enabled. The repair is
cached once per target and recorded in each native build report. A changed SDK
source fails closed until this compatibility repair is reviewed or removed.
This is maintenance of existing MIT exception EX-002, not newly admitted code
or a project-wide relicensing claim. Archive workers additionally transfer the
result dictionary under their mutex before consumers can attach engine objects.

Stop processes that have the DLL loaded before rebuilding it. Output publication uses a completed temporary DLL; a failed build does not overwrite the previous one. Hot reload is disabled. The C++ addon uses Godot's official bindings from the downloaded package; the prebuilt distribution itself is community-maintained. Its MIT license accompanies our linked addon.

Windows terrain now uses the typed godot-cpp binding in `terrain_binding.cpp`; the old manual `godot_bridge.cpp` is excluded from this build. The native field, mesher and save codecs remain shared with the original core. Cancellation lives in each binding instance and survives reset/load; ordinary native access is serialized per instance. Tests compare field, snapshot and mesh bytes with the published legacy DLL. See [terrain native validation](TERRAIN_NATIVE_VALIDATION.md). This does not migrate the GDScript terrain/forest schedulers, add replication, or lift the single-scene-world guard.

## Current native surface

`NativeEntityStore` is a bounded, dense entity pool with stable generation-checked handles, batch creation, native kinematic updates and bulk MultiMesh transform output. It creates no per-entity scene nodes. Mutations belong to one simulation thread; concurrent access is not supported. Handles are local to one store. Pool memory is capped at 262,144 entities; invalid inputs and capacity exhaustion return failure without partial mutation.

This foundation intentionally does not claim collision resolution, vehicle dynamics, gameplay AI, network replication, or a complete multiplayer entity system. Those require explicit integration and separate tests.

## Upgrade policy

Update the lock to a matching published SDK/toolchain pair, review its ABI metadata, download it once, rebuild only our extension, and run the real-engine tests. Single/double precision, compiler ABI and platform archives are not interchangeable. The supplied release is Windows-only; other platforms need matching prebuilt releases before we claim support.
