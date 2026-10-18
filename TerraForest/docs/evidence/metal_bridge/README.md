# Metal-railed footbridge - 2026-10-18

Selectable main-world prefab: Timber footbridge with metal rails - 12 m span. It uses 56 ordinary wooden blocks for the deck and stair approaches and six existing batched metal guardrail models. Paid gameplay costs 56 wood and 24 metal; editor placement remains free. The original all-wood bridge stays available. No additional per-bridge runtime script, simulation or mesher.

The explicit attachment envelope includes rail collision proxies outside the deck and a centimetre of clearance for transformed bounds. Initial exact-edge bounds passed at the origin but failed at a translated quarter turn (rejected_envelope.log). The corrected main-world test passes. The next run exposed a fixture mistake: starter materials were already sufficient, so the supposed rejection placed a bridge and the second placement correctly rejected occupied cells (incorrect_fixture.log). The final test explicitly removes starter metal before checking unaffordable placement; both rejected world and inventory snapshots remain identical.

Final graphical traversal passes at fullscreen 1920x1080: walk up stairs, cross the gap, return, and stop against the side rails. Snapshot restore and editable block capture pass. bridge.png was visually inspected. The separate actual-world test places the paid rotated bridge, saves through the normal world browser and verifies exact blocks, batched models and inventory in a fresh process. Unique disposable slots only; human saves unchanged.

Reproduce with tools/run_godot_check.py bridge_traversal --timeout 40 --require 'BRIDGE_TRAVERSAL failures=0' -- --metal-rails, and bridge_metal_persistence --timeout 90 --require 'WORLD_BROWSER_ROUTE failures=0' --headless. The latter launches graphical actual-world children.

These are functional checks, not sustained performance or thermal qualification. The main-world persistence placement is elevated to isolate saving; the traversal fixture uses block banks. Manual bank alignment is still required. Whole-footprint foundation grading must not be used across the gap. Automatic siting, structural failure and vehicle crossing remain unqualified. Water unchanged.
