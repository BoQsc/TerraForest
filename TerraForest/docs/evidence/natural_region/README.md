## Natural-region generation 14 — 2026-10-20

A separate immutable generator profile changes mountains from four smooth bumps to
warped, ridged landforms and introduces irregular lake boundaries inside existing
water catalog limits. It retains the accepted static water implementation. Native
woodland distribution now uses a coherent multi-scale field across all quadrants
for generator14, instead of the legacy southwest-only mask. The 36 candidates per
owner, stable IDs, resident limits and existing tree assets/LOD remain. Earlier
generators retain their original terrain and tree distribution.

The first rendered review exposed submerged trees: rendered roots sit 20 cm below
ground, while the water probe reached only 8 cm above them. Tree exclusion now probes
the supported ground surface; final lake views no longer show those submerged roots.
Ground-cover shelter queries use the same new tree field.

Full district generation and fresh-process restoration passed for seed42, slot
`natural_region_42_20261020`. Seven-seed northern lot fits pass. Native woodland
checks show deterministic candidates in all four quadrants, clearings and wooded
owners, bounded to36 candidates each. Legacy scatter byte-compatibility checks pass
(576 byte checks, 72 legacy cases). Native debug/release addons built using pinned
Zig/prebuilt godot-cpp. Final graphical inspection completed at1920x1080 fullscreen.

Inspected lake, shoreline and mountain images show broader woodland coverage and
less regular landforms. This is NOT full natural-world acceptance. Lake terrain still
has a basin-like rim, roads remain four straight spokes, settlement ground/layouts
remain too regular, and distant forest cutoff is visible from elevated views. Those
are required subsequent generation/representation work. Captures use a short settling
period; they do not qualify full residency, travel stability, sustained60FPS or older
laptop thermals. Next priority: terrain-following road corridors with shared map
geometry, followed by settlement clusters fitted to those corridors. Do not return
to loading micro-optimization as the main milestone.

