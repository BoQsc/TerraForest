# Mixed neighborhood — 2026-10-15

Coverage: M2 reproducible settlement generation and M3 usable buildings in the
combined world. Existing native frontage composition, grading and transactional
placement are reused. The optional `--layout mixed` authoring preset selects the
registered enclosed cottage and furnished three-floor tower, two lots per side,
two connected streets, seed 1703. Default cottage preparation remains available.

Published separate slot: `mixed_neighborhood_review`. Retained staging source:
`combined_stage_7801173ed84740ee91a1b06e51a3298b`. Existing saves are never replaced.
The launcher creates and verifies a unique staging save before publication.

Observed content: five cottages, three towers, 6,771 blocks; 8 doors, 166 windows,
15 guardrails, 23 tables, 23 chairs, 14 shelves and 14 chests (263 attachments).
Creation and a separate reopening process compare exact native snapshots for all
these models, blocks and road anchors, plus saved player start. Both passed.

The entrance fixture clones the review save, verifies eight doors, and uses the
production movement controller with held W, actual street terrain sampling and
E interaction. Every approach ascends, stops at the closed door, opens it and
enters on foot without jumping. Source save hash stayed unchanged. This does not
claim continuous walking between all buildings, tower upper-floor traversal in
this layout, vehicle travel, crowds, endurance or city density qualification.

Retained failures: the initial 60 s cold startup allowance expired while generated
water caches were preparing. Offline preparation now allows 180 s startup with a
270 s process ceiling. Actual creation took 92.98 s; reopening verification 34.47 s.
These are full fixture durations, not frame measurements. Initial invalid-addon-
capture messages occurred during generation; final compound publication and exact
reload passed. Water implementation was not changed and its startup behavior is
not considered resolved. The first entrance test placed tower approaches below
ground by assuming cottage foundation height; using the actual street surface
corrected the fixture. Both entrance logs are retained.

The 1920×1080 overview was inspected at reports/mixed_neighborhood/overview.png.
It confirms the mixed exterior layout only; no performance claim from its FPS HUD.
Eight Python preparation tests also pass (exclusive destination, invalid layout,
both-process preset forwarding, failure prevents publication and lock behavior).
