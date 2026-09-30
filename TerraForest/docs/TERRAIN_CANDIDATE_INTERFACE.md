# Reusable experimental native region interface

The candidate's geometry generation, output limits, rolling edge map and
cancellation contract now live in
`addons/volumetric_terrain/native/experimental/region_mesher.hpp`, under
`terraforest::experimental`. The benchmark includes that implementation rather
than maintaining a separate algorithm copy. It is not registered or compiled
into the game GDExtension. The world-specific rolling sampler and diagnostic
reference comparisons remain in the probe.

`mesh_layers` consumes a synchronous provider of two contiguous density planes;
`mesh_field` is the checked full-buffer adapter used by controls. The interface
accepts widths 1–32 m and regions wholly inside the current 2000 m world. This
is a local reconstruction primitive, not a large distant-patch implementation.
The caller owns immutable sample storage for the duration of the call, and must
provide the advertised plane span. A raw pointer interface cannot detect a
non-null pointer to an undersized or invalid allocation. The quantized sampler
provides the candidate's established biased-zero convention.

Region dimensions and coordinates are checked before calling the provider or
allocating output. Limits exceeding the 32-bit index/count domain are rejected.
The full-buffer adapter checks its exact sample count. Null provider results and
nonfinite sample values return `invalid_input`, discarding any partial geometry.
The internal crossing-bound assertion also returns an explicit error rather than
terminating the process. Successful output remains byte-identical to the prior
candidate fixtures.

Fifteen rejection controls cover negative/out-of-world origins, zero/negative/
oversized widths, integer-maximum values, oversized output limits, a truncated
full field, a null provider and NaN/infinity at a later height plane after
geometry has accumulated. Invalid regions never call the provider. All rejection
results are empty and release their output buffers. The full probe passes
**27 checks**, including the existing geometry hashes and cross-thread epoch test.

This refactor is preparation for integration, not completion of it. The interface
still uses standard containers without recoverable allocation-failure handling.
Sampler setup cancellation, field-error acceptance, LOD, normals/materials,
render/collision packets and Godot-worker integration remain unresolved. Per-plane
finite checks add work and no new speedup claim is made.

Run `python tools/probe_terrain_tetra.py`. Evidence and the new header hash are
retained in `docs/evidence/terrain_candidate_interface/`.
