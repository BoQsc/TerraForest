# Settlement actor authoring and fresh reopen, 2026-10-15

A cloned combined_gameplay world is loaded without --actors. The Actors HUD's
Enable button initializes the native pool. Place at aim creates an actor using
an actual street physics hit, Select/send chooses its exact body, then the same
button sends it to another real street hit five metres away. After 300 ordinary
native adapter updates it reaches within 30 cm and reports arrived. No position
injection or direct order assignment is used for the actor. The fixture positions
the player/camera and emits Button.pressed rather than operating an OS mouse.

Normal compound shutdown saves. A second engine process with --actors loads the
same slot and compares the entire actor store and order snapshots exactly; the
saved actor activates again. Both phases pass. Fullscreen1920x1080/cap60;
canonical combined_gameplay SHA256 unchanged. The screenshot was inspected.
Startup terrain-receive hitches of143.1ms/149.65ms are retained in logs; this
functional check makes no new performance qualification.

The successfully reopened clone was published once as settlement_actors.
Review Settlement Actors.cmd opens that independent checkpoint. Existing copies
are never overwritten. The runner can prepare a fresh checkpoint if absent.
The normal terrain player-pose save is used; camera framing is a test fixture,
not an assertion that the exact screenshot orientation restores. World actor
identity, position and order restore are explicitly verified.

No water or native runtime changes. This completes a human-reviewable authoring
loop, not NPC jobs/dialogue, long-distance navigation or large-crowd qualification.
