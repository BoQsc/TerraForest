# Cheap terrain locality decision probe

Release-engine run completed in 2.84 seconds including startup. No native or
gameplay changes were needed. One actual radius-2.5 excavation at (1296,1296),
seed 1703, is held constant while enclosing patch size changes. Three measured
queries per size follow warmup, alternating size order.

| Enclosing patch | Native mean ms | Remaining ms if extraction/connectivity were free |
|---|---:|---:|
| 16 m | 1.70 | 0.87 |
| 32 m | 5.52 | 2.99 |
| 64 m | 24.33 | 17.13 |
| 128 m | 67.60 | 41.45 |
| 256 m | 251.98 | 156.99 |

The current runtime LOD-step rule is used: max(1, size/32), capped naturally at
8 by these sizes. The remaining time is measured total minus the native
extraction/connectivity stage, not a measured replacement implementation.
Surrounding terrain differs with patch extent; the edit and underlying field
remain unchanged. This tests enclosing rebuild amplification, not edit-history
scaling or a homogeneous synthetic complexity curve.

**Reject extraction-only optimization as sufficient:** even its optimistic
zero-cost ceiling exceeds the whole 150 ms edit target at 256 m, with no room for
queueing, publication or collision integration.

Four 16 m owners meeting at the edit corner take **5.30 ms combined**, averaged
over three groups. This is promising component evidence for local reconstruction;
it omits cross-region lighting invalidation, LOD seams and atomic publication.
It is not an achieved interaction latency.

**Reject replacing the entire distant patch with fine regions:** one 256 m
step-8 patch takes 220.96 ms, 11,336 triangles and 488,212 encoded bytes. The same
horizontal extent covered by 256 step-1 regions takes 312.49 ms in summed native
queries, 151,328 triangles and 12,061,248 bytes: 13.35× triangles and 24.71× bytes.
Duplicated halo vertices and fine detail are included in those actual outputs.
The experiment does not submit draw calls or establish GPU cost or seam parity.

The replacement must therefore separate local mutation/reconstruction from
distant visual representation, with bounded lighting and publication work. A
prototype should first prove cross-region surface/LOD continuity and acceptable
distant geometry cost. Larger architecture work is not justified by the 5.30 ms
local number alone. The foundation remains unqualified.

Reproduce:

```text
python tools/test_native_release.py --addon volumetric_terrain --test terrain_locality_probe --godot PATH
```

Raw samples, log and source/DLL hashes are retained in
`docs/evidence/terrain_locality/`. These are headless native measurements, not
1920×1080 performance results. All graphical qualification remains fullscreen
1920×1080 at full render scale.
