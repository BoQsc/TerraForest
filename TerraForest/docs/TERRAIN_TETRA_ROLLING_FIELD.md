# Two-plane sampling for the isolated terrain candidate

The candidate now has a sampling path that stores only two adjacent density
planes, one cached procedural height per XZ position, and one cached page index
per XZ position. Page indices refresh when sampling crosses a 16 m page boundary.
The lower density plane is replaced as meshing advances upward. The common mesh
loop accepts either the full-buffer control or this sequential plane provider.

| Region width | Full density buffer | Two density planes | All sampler payload |
|---|---:|---:|---:|
| 16 m | 297,092 bytes | 2,312 bytes | 4,624 bytes |
| 32 m | 1,119,492 bytes | 8,712 bytes | 17,424 bytes |

All sampler payload is `16*(size+1)^2` bytes of vector elements on the pinned
toolchain: two float planes, float heights and integer page indices. It is
independent of world height. This excludes vector/allocator overhead, crossing
maps, output geometry and diagnostic reference buffers. The prototype still
stores the full field separately for validation and residual measurements, so
these figures are not its whole-process memory consumption.

## Validation and limits

Every streamed plane is compared byte-for-byte with authoritative quantized
samples. All fifteen streamed meshes match the full-buffer outputs exactly;
the existing immutable hashes, topology and partition checks remain passing.
Additional sampler-only controls cover (0,0), a region crossing negative X, and
a region crossing the world's far X/Z boundaries, including all 257 Y samples.
No out-of-world mesh-ID claim follows from those sampler controls.
The complete probe passes **24 checks**.

Streaming total time includes height setup, page queries, sampling, meshing and
the diagnostic plane comparisons. It is measured once per fixture after the
paired full-buffer tests and is not an alternating-order speed comparison. No
speedup claim is made. Sampling still evaluates every vertical lattice plane;
this reduces retained storage, not the number of density evaluations.

The sequential sampler has no full-volume allocation of its own and accepts a
null reference pointer when validation is not requested. The test supplies the
reference explicitly and retains both implementations. No game DLL changes.
Output growth, material/lighting support, field-error acceptance, LOD construction,
cancellation and runtime integration remain unresolved adoption requirements.

Run `python tools/probe_terrain_tetra.py`. The report, per-fixture storage and
timings, boundary controls and source/toolchain hashes are retained in
`docs/evidence/terrain_tetra_rolling_field/`.
