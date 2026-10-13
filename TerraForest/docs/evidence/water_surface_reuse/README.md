# Shared terrain surface primitives — 2026-10-13

The live terrain core now calls the extracted surface-nets cell representative and face-connectivity helpers in surface_cell.hpp. Debug and release native DLLs are rebuilt for this refactor. Water's runtime mesher has not been switched.

Validation: 32,768 representative cases match the original arithmetic bit-for-bit; 7,168 connectivity cases preserve ordered faces and winding with absent neighbours. Six complete encoded generated terrain patches match core.cpp from commit 54cdc87. Both surface-style settings were exercised on unedited patches; this is not edited-terrain visual qualification or a performance comparison.

Run tools/check_surface_cell_reuse.py for the comparisons. Run tools/check_water_surface_sampling.py for the admission diagnostic below. These use the pinned Zig compiler and do not launch the game.

## Rejected conversion

A direct 0.5 m regular-grid density conversion is insufficient. The diagnostic uses the shared live terrain representative on the exact sign field of a 2x2 m water volume. A 1 m deep pool produces 32 surface cells. A 4 mm layer (equivalent to one litre per 0.5x0.5 m cell, 16 litres across the fixture) produces no surface cells at 992 of 1,000 tested vertical offsets through one grid spacing. Eight offsets are detected. Counts are geometric coverage, not timing or conservation evidence.

The diagnostic exits successfully when it reproduces this rejection; it is explicitly not a passing water implementation. Finite volume is still present in the input while its rendering samples miss it. This result does not reject all density-based water representations or prove the existing custom mesher preferable.

## Required next work

Preserve thin interfaces explicitly in the water-to-surface adapter, with consistent ownership across region boundaries. Prove tiny-puddle coverage, separation across solid barriers, lake flatness, and seam agreement before replacing runtime surface generation. Bucket/depth queries must agree with that same surface. Retain integer authoritative quantities and the existing save format unless a demonstrated storage change is required. Do not fix missing thin layers by globally increasing grid resolution or silently thickening stored volumes.

Held-mining scheduling was fixed earlier; moving-water stepped edges and response latency remain open. No new runtime or optional competing water implementation was added by this extraction.

## Thin exposed-interface adapter

water_surface_interval.hpp derives an exposed interface from integer millilitres and the existing floor/ceiling interval. It chooses the slab below an exact lattice-height surface and supplies signed sheet samples to the shared terrain representative. It does not create an additional water store or change authoritative quantities. Signed sheet samples are rendering inputs, not a closed liquid density field; they must not be used for collision, flow or volume integration.

The numerical probe covers 507 world cell heights and 72 floor offsets (36,504 cases), including capacity-limited thin films. Reconstructed heights agree within 0.04 micrometres in local arithmetic. Separate supplied sheets within one cell remain distinct in this calculation. Dry/solid inputs are rejected and overflowing amounts are capped for rendering, not deleted. This does not prove the still-unimplemented connected-sheet selection, physical volume accuracy of a smoothed mesh, finite-footprint meshing, region seams or bucket targeting. The interval height and same-layer connection helpers are now called by the runtime mesher; bucket traversal uses the same connection helper. Sheet sampling itself is not yet wired into runtime geometry.

Godot was found in the normal Steam directory under the renamed executable Godot Engine.exe (4.7.2.stable.steam.ed1daf0bf). tools/run.py now recognizes both names. Release native tests pass 14 surface-continuity and 15 shoreline/bucket assertions after adopting the shared interval helpers. No new graphical qualification or performance claim is made.
