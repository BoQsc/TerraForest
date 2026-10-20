# Moving-camera TAA comparison - 2026-10-20

Read-only southern_mixed_42_20261018 world; temporary scene; 1920x1080,
60 FPS cap, RTX 4050 Laptop. Test: tests/vegetation_motion_diagnostic.gd.
Three identical six-metre camera paths: normal, TAA, normal repeat.
Wind disabled. Removal storage unchanged; no rejected publications.
Godot exited normally with zero failures.

| Setting | GPU median ms | Frame p95 ms | Worst ms |
|---|---:|---:|---:|
| Normal | 7.207 | 17.195 | 21.954 |
| TAA | 8.689 | 17.329 | 33.567 |
| Normal repeat | 6.976 | 16.860 | 18.032 |

Normal frame 58 and TAA frames 58/59 were inspected. TAA softens jagged detail
but the far-field speckled pattern remains. No production settings changed.
The added GPU cost is not justified as a fix for this defect.

Timing uses a separate pass without screenshot readbacks. Image replay captures
consecutive camera poses, but synchronous PNG capture slows that replay (including
the visible 2 FPS HUD). This is NOT gameplay FPS, nor a real-time video or a
quantitative proof of temporal stability. The pattern survives TAA during camera
movement; this does not certify smooth motion.

Sparse placement is implemented. Distant representation quality and streaming
continuity still need acceptance. Isolate species/representation contributions
before changing models or density. Strict sustained 60 FPS remains unproven.
User saves were not written.
