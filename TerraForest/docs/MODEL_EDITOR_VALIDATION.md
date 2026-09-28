# In-world static model placement

The main world now exposes its native static placements through an object catalog, ghost preview, quarter-turn rotation, insertion and picking/removal. Metal beams and floor panels share the registered box mesh with different placement scales; doorways use the compound architectural asset. No node is created per authored object. A GDScript addon provides editor UI/input only; C++ owns authoritative insertion, ID allocation, validation, spatial updates, collision and serialization.

## Verification

- 104 placement checks passed in debug and isolated release builds. Added cases verify read-only preflight, automatic live-ID uniqueness, player protection, invalid transform atomicity, allocation after restoration and signed ID overflow rejection.
- 80 integrated world checks passed at 1920×1080 exclusive fullscreen, full render scale. Actual tool key/mouse handlers select and rotate a doorway, place its preview transform, invalidate the compound save cache, wait for collision, remove by picked stable ID and return to block editing. Existing terrain/block/prefab/history/physics tests remain covered.
- The rendered catalog and model preview were inspected. Reports, build hashes and the screenshot are in [evidence/model_editor](evidence/model_editor).

Reproduce with `tools/build_native.py --addon structures --target all`, `tools/validate.py --test static_placements`, `tools/test_native_release.py --addon structures --test static_placements`, and `tools/validate.py --test structure_world --gpu`, using `--godot PATH` for engine tests. Builds use the pinned Zig/prebuilt godot-cpp SDK; runtime is Godot 4.7.2 Steam and graphical checks use GTX 1060 Max-Q Vulkan Forward+.

## Current limits

The preview checks supported surface direction, native capacity/transform validity and player clearance. Overlap with existing structures/terrain/vegetation is allowed; full-footprint support and slope fitting are not implemented. Collision can still be pending or deferred by its independent budget. Picking/removal requires nearby resident physics. Native automatic IDs are unique within live data and may be reused after deletion/restore, so multiplayer must supply its own authoritative identity policy. The initial three-entry catalog has no import UI, move/scale handles or object undo/redo. These and the remaining world objective are tracked in [delivery status](DELIVERY_STATUS.md).
