# Foundation: localized vegetation support

Small terrain edits previously removed roots across entire 16 m columns, at all
heights. Persistent modification metadata then prevented otherwise supported
trees from returning. Updating an owner also recreated all surviving renderer
rows, resetting their LOD transitions.

Terrain publication now queues only intersecting 64 m placement owners for
bounded asynchronous support revalidation. Live vegetation remains until the
result is ready. Epoch/revision checks reject stale results. Native command 17
accepts 1–64 candidate positions and evaluates interpolated terrain density near
the original surface. The ecosystem submits at most 36 candidates per owner,
one batch per frame, with at most two batches in flight. This replaces seven
script-to-native point requests per candidate with one native batch and packed
array decoding. Unchanged renderer rows survive changed-owner publication.

The support tolerance is 0.35 m above/below the original surface. This is a
procedural placement rule, not a tree-root physics simulation. Restored support
may restore a tree. Chopping persistence remains a separate requirement.

Validation on Godot 4.7.2:

- Native debug and release: 31 checks each, including fractional support,
  underground excavation, small surface excavation, and malformed batches.
- Existing field, snapshot, and mesh fingerprints retain legacy byte parity.
- GPU integration: 42 checks at 1920×1080 fullscreen, full render scale, Vulkan
  Forward+ on GTX 1060 Max-Q. Underground mining preserves every resident tree;
  a 1.5 m surface excavation removes only the unsupported tree; unaffected
  stable IDs survive travel away and return.
- Combined terrain/forest/building GPU correctness test: 167 checks, including
  block/model vegetation exclusion, demolition, persistence and player readiness.

Reports and tested source/DLL hashes are retained in
[the evidence directory](evidence/vegetation_support/source_hashes.json).

These are correctness checks. They do not establish sustained 60 FPS, mining
latency under accumulated edits, combined city capacity, or long-session memory
stability. The terrain stream is paused in this integration fixture. Profiling
repeated mining in the fully streaming world remains the next foundation gate.
