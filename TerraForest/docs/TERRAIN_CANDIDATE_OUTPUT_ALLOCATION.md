# Recoverable candidate output allocation

Candidate position and index storage now use a move-only `FallibleBuffer` for
trivially copyable elements. Growth checks byte-count overflow, requests a new
allocation, constructs/copies live elements and releases the previous allocation
only after success. A failed allocation leaves the previous buffer intact until
the mesher deliberately discards the incomplete result. No C++ exceptions are
required; the probe remains compiled with exceptions disabled.

The mesher returns `allocation_failed` separately from output limits,
cancellation and invalid input. Existing element limits still clamp growth
requests. Custom allocation/release hooks permit deterministic failure injection;
their context must outlive every returned buffer and supply correctly aligned
storage. The buffer is an internal primitive: unchecked element append/access
requires the mesher to reserve and validate first.

## Evidence

The alternating-layer fixture needs 30 position/index allocation calls. The
probe fails each call in a separate build. All 30 return allocation failure with
empty geometry and zero live tracked output buffers. A subsequent successful
build matches reference bytes, and moving the result transfers ownership without
leaks or duplicate frees. The complete suite passes **29 checks**; all fifteen
immutable real-field mesh hashes remain unchanged.

This is **partial allocation recovery**, not an out-of-memory-safe terrain system.
The crossing hash map and sampler vectors still use standard containers with
unrecoverable allocation failure in this exceptions-disabled implementation.
World data, renderer/physics resources and diagnostic controls are outside the
injected allocator. Growth temporarily holds both old and new output allocations;
logical element ceilings are not a hard peak-byte budget. No overall allocation
budget or performance gain is claimed.

The change is confined to the experimental native candidate; the game extension
does not register or call it. Run `python tools/probe_terrain_tetra.py`.
Evidence and source/toolchain hashes are in
`docs/evidence/terrain_candidate_output_allocation/`.
