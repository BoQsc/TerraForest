# Saved pickaxe no-op — 2026-10-26

Calm_Meadow, seed 1703; saved player feet `(1066.871, 42.01955, 1097.791)`.
The original collision hit was `(1067.436, 41.87583, 1097.498)`.
Three original pickaxe digs were accepted but all returned `changed=false`, with
the same collision contact after every strike. This was not a blocked input,
zombie hitbox, inventory limit or slow worker. Reapplying the same 0.65 m CSG
sphere between lattice samples could not remove the remaining visible surface.

The new player-only native contact mode minimally shifts that sphere to include
a nearby exposed solid sample. It runs inside the ordered worker, not a new
per-frame query or a retry loop. Standard sculpt brushes, terrain generation,
building grids, save formats and player saves remain unchanged. Invalidation and
vegetation-support capture include the bounded centre displacement.

Source and release checks include rendered triangle contacts, repeated fixed-ray
digging from seven directions, exact resource yields, empty/protected/outside
contacts, invalid packets, paged residency and binary roundtrips. The saved-world
replay separately checks three actual animated mouse clicks and three offscreen
graphical contacts against an isolated copy. Every strike must change density
and move matching collision; input must retain windup, one contact and one wear.
This is finite regression coverage, not exhaustive terrain or performance proof.

Retained intermediate harness failures: the headless animated replay could not
start swings (15 assertions failed); it is not counted as a pass. The graphical
input fixture replaces that unsupported route without overriding production
input guards. The first release invocation passed native assertions but failed
because the new test had not written the runner's required JSON report; that
reporting contract is now implemented. A packaged native run also passed its
assertions but reported an error trying to create a virtual `res://reports`
directory; the test now creates the resolved filesystem directory instead.
That failed runner result is retained. Original diagnostics checked loading and
capture only: their process-success flag is not a mining-success assertion.

Reproduce:

```
python tools/check_saved_mining.py --slot Calm_Meadow --pack
python tools/check_terrain_editing.py --native-only --case terrain_contact_mining --case terrain_edit_recovery --case terrain_edit_paged_recovery --case terrain_material_items --case mining_rewards --case terrain_history_storage
python tools/test_native_release.py --godot "<Godot executable>" --addon volumetric_terrain --test terrain_contact_mining
```

Raw results, source-save hashes and installed-build identity are recorded in
`qualification.json`; compressed logs retain both failures and successful reruns.
The copied save is retained locally rather than committed. Before/after captures
show the exact same saved aim. Rendering/focus-switch performance work documented
in the main status file remains deferred; this change does not claim to close it.
