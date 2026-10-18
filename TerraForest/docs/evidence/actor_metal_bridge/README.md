# Residents on the metal-railed bridge - 2026-10-18

The existing actor bridge test now constructs the real structures addon and places its prefab through NativePrefabPlacement, including registered batched rail attachments. Navigation readiness uses the combined block/model collision query. The --metal-rails flag selects the production metal bridge; --opposing enables two residents with opposite two-point patrols. Existing all-wood selection remains available.

At fullscreen 1920x1080, both residents completed outbound and return legs. Minimum capsule-segment separation was 0.789158 m (required >=0.699 m); minimum centre height 0.899954 m (required >0.85 m). Route work stayed at the existing cap of 12 and active bodies at two. Screenshot inspected: both banks, steps, deck and metal rails are present. No runtime navigation, collision budget or content was changed to pass the test.

Reproduce: python tools/run_godot_check.py actor_bridge --timeout 45 --require 'failures=0' -- --opposing --metal-rails.

This verifies interaction between the production bridge geometry and bounded resident patrol. The fixture uses block banks and fixed collision residency, not a terrain river crossing or main-world travel/streaming. It does not qualify dense crowds, long-run frame times, thermal headroom or vehicle crossing. Water and human saves are unchanged.
