# Paid staged world persistence - 2026-10-18

The actual-world metal bridge persistence test now uses the direct staged world entry point instead of bypassing it with synchronous construction_inventory.place_prefab. The ordinary gameplay inventory, structures, preparation coordinator and world-browser save/reopen path participate. The disposable placement is elevated and rotated one quarter turn to isolate the transaction from terrain grading.

Verified: insufficient metal rejects all edits and preserves inventory; changing inventory after staging begins cancels without losing the added item or touching the world; initiating a valid placement does not charge materials; successful publication consumes exactly 56 wood and 24 metal and installs the rotated deck and six batched rails. Ordinary saving and a fresh process restore byte-identical structures and inventory. Both children run fullscreen 1920x1080.

The first run failed a fixture assertion that compared the rotated deck word with the unrotated word (33 rather than 41). The failure is retained. No runtime change was made; the corrected test passes. This evidence covers paid staging and persistence, not natural bank positioning, a rendered city workload or sustained frame-time qualification. Original human saves and water unchanged.

Reproduce: python tools/run_godot_check.py bridge_metal_persistence --timeout 90 --require 'WORLD_BROWSER_ROUTE failures=0' --headless. The parent launches graphical world children.
