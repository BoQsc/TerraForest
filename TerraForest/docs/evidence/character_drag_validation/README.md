# Character drag validation — 2026-10-18

Character equipment rejects malformed source fields and invalid destination slots before indexing inventory. Both inventory and equipment revisions must match; rejected drops preserve state.

Validation: `python TerraForest/tools/run_godot_check.py character_drops --timeout 65 --require failures=0 -- --gameplay-construction`.

Final graphical actual-world run: 33 checks, zero failures. Covers malformed slots, normal mouse equip/unequip, equipment persistence, whole/half world drops and recollection, and no-support rejection. Temporary world; human saves untouched. This is functional coverage, not performance qualification.

The initial run exposed an obsolete test expectation: one existing pickup no longer blocks every drop because runtime tries five positions. The corrected fixture disables its elevated support, establishing no reachable ground for every candidate. Runtime placement policy was not changed to satisfy the test. Initial failure retained alongside final evidence.

User direction: defer quick-use food and player health/hunger; continue world systems. Leave accepted water implementation alone.
