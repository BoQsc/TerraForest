# Moving-water surface diagnosis — 2026-10-13

One frozen published geometry state, captured from the ordinary combined-world repeated-mining test. Water processing is paused during the diagnostic captures. Normal material, top-only material, opaque face classification (cyan nonvertical, red vertical), and terrain-only views share geometry and camera. Debug materials exist only in the test. Shader diagnostic warm-up is excluded from performance sampling.

Vertical strips occur throughout moving water, not only at the bank. Hiding vertical faces exposes gaps. The stored water snapshot is captured at the same pause; its regional geometry can include earlier publication states, so cell counts must not be mistaken for exact pixel attribution.

The snapshot analyzer finds 1135 exposed cells; adjacent-column pairs include 1944 same-layer connections, 288 connected cross-layer pairs, and 525 cross-layer pairs rejected because the cell below the higher exposed cell is not full. Nine pairs have a solid floor and three same-layer pairs lack a wet opening. Examples include deficits of 143–198 ml (0.572–0.792 mm over a 0.25 m2 cell), and larger gaps. The solver retains upper water while lower cells have lost water laterally; the renderer consequently exposes multiple interfaces in a column.

This explains a substantial class of disconnected moving surfaces, but does not prove all visual artifacts have the same cause. The required next step is a bounded conservative vertical-consistency operation in the flow update, with adversarial ordering and exact-quantity tests. Do not simply drop vertical faces or smooth across actual solid barriers. No physics or mesher-completion claim is made by this diagnostic. All 46 existing world checks pass, demonstrating why their previous scope was insufficient.

Reproduce the diagnostic with tools/check_regional_water_world.py, then tools/analyze_water_surface_snapshot.py. The binary is a test-owned frozen water snapshot, not a user save.
