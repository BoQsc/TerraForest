# Static model and vegetation reconciliation

The ecosystem now queries authored blocks and registered static models together. Native model queries use a maintained 32 m group-bound index and configured compound proxy parts, falling back to mesh bounds for collections without collision metadata. Overlap is independent of nearby physics admission: distant, disabled or budget-deferred collision cannot make a saved model invisible to vegetation exclusion.

`NativeStructureQueries` combines block and model masks in C++. The structures adapter forwards change notifications to the existing bounded ecosystem reconciliation queue. Model placement, removal, restoration, proxy reconfiguration and collection transform changes all trigger reconsideration of cached candidates. No extra vegetation save file is introduced.

## Verification

All 116 native placement checks passed in debug and release, covering disabled/far physics, signed group boundaries, edits/removal/restoration, compound openings, transformed collections, input bounds and invalid model collections. All 89 fullscreen world checks passed, including real-tree placement/removal, collection motion, exact deterministic regrowth, restored model data and forest-residency reset checks. The suite also verifies that all resident tree bounds are clear of both blocks and model proxies after reconciliation. The compound persistence regression passed all 59 checks.

Reproduce with `tools/build_native.py --addon structures --target all`, `tools/validate.py --test static_placements`, `tools/test_native_release.py --addon structures --test static_placements`, `tools/validate.py --test structure_world --gpu` and `tools/validate.py --test structure_persistence`, supplying `--godot PATH` for engine runs. Zig 0.16.0 reuses the pinned prebuilt godot-cpp 4.7 SDK. Graphical checks use Godot 4.7.2 Steam, 1920×1080 exclusive fullscreen at full scale, Vulkan Forward+ on GTX 1060 Max-Q.

Reports, build hashes and inspected imagery are retained in [evidence/model_exclusion](evidence/model_exclusion).

## Limits

Exclusion uses conservative transformed AABBs of proxy parts, not exact triangle intersections. Rotation/shear can clear more vegetation than the precise model surface. A collection without proxy metadata uses its whole mesh bound. Native queries accept at most 65,536 candidates and the combined query accepts at most 256 model collections; normal ecosystem batches contain at most 36 candidates. Dense overlapping groups can still require substantial work; these limits do not establish a frame-time budget or city-scale headroom.

Group bounds now remain available even when physics is disabled, adding bounded index maintenance to authoring. Changes queue all cached ecosystem owners and reconcile one owner per frame (up to 169 frames at the default cap). Trees can briefly overlap newly placed objects while that queue drains. In-place mesh-bound edits require asset reconfiguration. Native forest scheduling, more vegetation species, region storage and long-duration validation remain unfinished.
