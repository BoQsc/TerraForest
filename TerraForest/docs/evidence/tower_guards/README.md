# Tower guardrails — 2026-10-15

Added a reusable 4 m metal guardrail to the object palette and construction recipes
(provisional cost: four metal). Seven baked bars share one mesh/material. One thin
continuous collision proxy prevents catching between bars. Native static batching,
bounded nearby collision, existing object durability and model persistence apply;
there is no per-rail tick or rigid-body simulation.

The three-floor tower adds five guardrail placements: both sides of each upper
shaft and the rear of the top shaft. Front landings and flight approaches remain
open for circulation. Twenty-four targeted checks pass, including walking toward
both upper sides and rear without falling, plus the complete stair ascent/descent.
Main-world grounded placement/traversal passes again; a fresh process restores the
exact guardrail snapshot, door state and window identities.

Commands:

- `python tools/run_godot_check.py tower_traversal --headless --timeout 45 --require "PASS low ceiling prevents unsafe step-up" -- --all-floors --furnished`
- `python tools/check_enclosed_cottage.py --grounded --tower`

The second command published `tower_review_guarded`. The launcher now opens that
slot; the prior `tower_review` and cottage review are preserved. The checks cover
walking, not jumping over guards, NPC navigation, final art, or city-scale cost.
Human review remains pending.
