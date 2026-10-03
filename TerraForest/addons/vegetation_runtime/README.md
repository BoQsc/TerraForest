# Native vegetation selection and sparse updates

Optional companion to `addons/vegetation`. Forest loads this extension when available; `--scripted-vegetation-selection` keeps the scripted reference path for comparisons.

`NativeVegetationSelection` handles cell neighborhood selection, visual/shadow LOD decisions, conservative camera-travel event scheduling, and sparse MultiMesh slot updates. Stable IDs are signed 64-bit values. Superseded event records are compacted when their count exceeds four times live events plus 1024. Root removal invalidates its event; resets clear scheduling state. Use `--scripted-vegetation-flush` to compare the original sparse update loop while retaining native selection.

This is a scene-thread adapter to the existing renderer's dictionaries. It is not thread-safe and its methods require the companion renderer schema. Transition completion, full cell rebuilds, node allocation, and cached cell membership construction remain in the existing renderer. Sparse updates remove before adding, preserve swap-removal mappings, and issue the same instance transform/custom-data writes. It does not change the rendered meshes or provide a GPU performance guarantee.

Build with `python tools/build_native.py --addon vegetation_runtime --target all` from the project directory. This uses the pinned prebuilt godot-cpp SDK and Zig toolchain. Windows x86-64 debug/release libraries target Godot 4.7. Other platforms require native builds.

Run `tests/vegetation_native_selection.gd` headlessly for scripted/native state and render-slot parity, instance transform/custom-data parity, empty-cell cleanup, signed IDs, queue bounds, fade-time wrapping, and LOD threshold checks. The graphical settlement editor test records whether each native path actually ran.

Project code is 0BSD. The godot-cpp dependency notice is retained in `GODOT_CPP_LICENSE.md`.
