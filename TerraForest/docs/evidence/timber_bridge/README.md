# Timber footbridge — 2026-10-16

New main-world prefab: Timber footbridge · 12 m span. All 92 cells are ordinary native wooden blocks: deck, four-step approaches, posts and slab rail caps. No per-bridge runtime script or physics simulation, no new native mesher. Gameplay costs 92 wood; editor placement stays free. Existing native greedy meshing, chunk collision, shape picking and save storage remain owners.

The graphical traversal fixture places the bridge between two separate block banks over an empty 12 m gap. Ordinary NativePlayerMovement walks up to midspan, crosses/descends, returns without jumping and is stopped by the side rail. Compound snapshot restoration and block capture pass. Screenshot bridge.png was inspected at fullscreen1920x1080. These are functional checks, not frame/thermal measurements.

The actual-world fixture finds the prefab in the construction catalog, rejects unaffordable placement with identical world/inventory snapshots, supplies fixture materials, places a quarter-turned bridge through gameplay accounting, saves via the browser and verifies exact bridge records and player inventory in a fresh process. Uses a unique disposable slot and an elevated placement to isolate construction persistence; it does not prove terrain grading or naturally positioned river crossings.

Initial attached-metal-rail proposal was rejected because current native prefab transactions require model proxies inside block-defined placement bounds. The final bridge uses editable block railings. Rejected log retained. General attachment-envelope support remains a separate construction limitation, not bypassed here.

Manual siting: align the approaches with banks at the prefab origin height; stairs occupy local z=-1 and12, deck z=0..11. Do not use whole-footprint foundation preparation across a gap: that tool fills a building site. Automatic bridge siting, structural support/failure, vehicle crossing and river generation are not provided by this prefab. Water remains unchanged.
