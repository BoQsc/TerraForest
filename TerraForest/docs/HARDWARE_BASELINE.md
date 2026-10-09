# Hardware change and performance comparisons

Recorded 2026-10-09 at code revision `f2df213543bbc246e0299798723ed357f63aa28b`.
The user changed computers and reports deliberately low machine settings.
Treat subsequent measurements as a new hardware cohort, not software speedups.

## New host: Lenovo 82XV

| Component | Observed configuration |
| --- | --- |
| CPU | Intel Core i5-12450H, 8 cores / 12 logical processors |
| Dedicated GPU | NVIDIA GeForce RTX 4050 Laptop GPU, 6141 MiB reported VRAM |
| Integrated GPU | Intel UHD Graphics |
| RAM | 16 GiB installed, two 8 GiB modules, configured speed 4800 MT/s |
| OS | Windows 11 Home, build 26200 |
| NVIDIA driver | 617.14 |
| Intel graphics driver | 32.0.101.6733 |
| Display resolution | Both Windows GPU records report 1920 x 1080 |
| Windows power plan | Balanced |
| Processor power policy | Minimum 5%, maximum 100%, both AC and battery |

Read-only inventory used Win32 CIM classes, `powercfg` and `nvidia-smi`.
One desktop snapshot reported 3.39 W GPU power, 43 C and 34% GPU utilization.
This was not a controlled idle or game measurement. It provides no sustained
thermal or performance qualification. NVIDIA power limit was unavailable.
Lenovo thermal mode, Windows power-mode overlay, GPU power budget, display
refresh rate and actual game rendering adapter were not verified. The Balanced
plan does not establish or override those settings. No settings were changed
and no load test was run.

## Comparison policy

Previous runtime logs identified an NVIDIA GTX 1060 with Max-Q Design. Previous
CPU and memory specifications are not established by this inventory. Preserve
old evidence as historical results; do not combine it with new measurements or
attribute cross-machine differences to code changes.

- Keep the project target at 1920 x 1080 fullscreen and 60 FPS.
- For optimization claims, run the before and after revisions on this same
  machine with the same engine, driver, power settings and rendering settings.
- Record the actual rendering adapter, resolution, frame cap, VSync, renderer,
  test seed/world, camera path, workload and cache state with each comparison.
- Record AC/battery state and known vendor thermal mode; label unknown settings.
  Re-establish a baseline after hardware, power mode or driver changes.
- Compare frame-time distributions, edit latency, queue behavior, memory and
  workload counts. Use power/temperature measurements for thermal questions;
  GPU utilization percentage alone is not comparable efficiency evidence.
- Use short targeted regression checks first. Passing on this machine does not
  prove the old machine meets the target or establish long-session stability.

This inventory is a provenance record, not a performance benchmark. A controlled
new-machine runtime baseline remains to be measured when the next relevant
test is run.
