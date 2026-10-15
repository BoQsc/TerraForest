# Extracted structures bundle component check

2026-10-15, Godot 4.7.2 Steam, Windows x64, Vulkan Forward+, RTX 4050 Laptop GPU.

Built with `python tools/package.py --addon structures`, then checked with
`python tools/verify_addon_bundle.py --addon structures --godot <engine.exe> --exercise-structures`.
All six `tools/test_package.py` checks also passed.

The verifier extracted the archive into a fresh temporary project, verified the
exact SHA-256 manifest, imported without a frame-delay workaround and loaded
104 resources. Only the test fixture was copied from the source project.
The runtime exercise launched at 1920x1080 fullscreen with a 60 FPS cap.

All 31 assertions passed: native initialization, four catalogs and baked icons,
window/guardrail/fence placement, removal without stale collision and exact
snapshot restoration; door opening, closing and hinge/model restoration.
The stored result identifies the archive and fixture hashes.

This qualifies the exercised standalone component paths only. It does not test
host-game input wiring, recipes, multiplayer authority, visual quality, large
populations or sustained frame timing. No runtime performance improvement is
claimed. Snapshot restoration here occurs in one process, not a fresh game.
