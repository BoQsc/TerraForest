# Conservative vertical consistency — 2026-10-13

Native flow now queues vertical underfill repairs whenever changed cells expose a shared vertical opening with water above. A priority operation transfers only the exact available amount across one face; subsequent gaps are queued. No unbounded column scan or global terrain resampling. Operations share the existing advance budget, with elapsed time checked every eight operations. Authoring fill completes before repair, preserving fill accounting. Solid boundaries and invalid cached terrain stop transfers.

Affected mesh regions and their reconstruction halo defer publication while repairs are pending. The existing awake save bit on the upper wet cell preserves unfinished repair work without changing the file format; restore reconstructs repair jobs. Queue entries are deduplicated. This is the existing water runtime, not a second implementation.

Release continuity tests: 20 assertions pass, including a one-millilitre gap propagated across four stacked cells with one-operation calls and mid-repair save/reload. Shoreline/bucket tests: 15 pass. Connectivity tests: two pass. Actual combined-world test: all 46 assertions pass, including held mining, repeated excavation, quantities, bucket and cached load.

Frozen-state adjacent surface pairs rejected for underfilled support fell from 525 in water_moving_surface_diagnosis to zero in this capture. The opaque face classification shows the dense internal strips gone. This is a particular captured scenario, not proof that every possible stored or edited world is normalized. Existing sleeping legacy states are not globally rescanned on load; affected/awake state is repaired.

The normal rendering still shows thin region seams and some shoreline gaps. Meshes publish across different frames, and shoreline clipping remains limited. These remain open; do not mark all water rendering complete.

Measurements: outlet response 1171 ms; frame median 16.665 ms, p95 16.792 ms, max 120.295 ms across 664 measured frames. Native pre-save maximum advance 1.008 ms and mesh 0.242 ms. The whole-frame outlier remains unqualified; this is not a sustained-60-FPS acceptance. Diagnostic shader setup and screenshot readback are excluded explicitly, but this is not an isolated performance benchmark. Dense moving columns and repair backlog fairness still need scale qualification.
