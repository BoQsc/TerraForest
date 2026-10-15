# Tool exhaustion and replacement loop

2026-10-15, actual temporary world, paid gameplay, generated ground cover,
1920x1080 fullscreen with 60 FPS cap.

`tool_replacement_world` passes the full interaction sequence:

1. The only initial supply is a pickaxe at wear 199/200. An ordinary attack on
   a placed wooden block breaks it and switches the held item to empty hands.
2. Empty hands successfully use the same attack path. The break notice names
   the tool and points to Tab → Crafting. An attempted replacement without
   ingredients fails and tells the player to gather the displayed materials.
3. E gathering removes three generated stones and two generated dry-twig
   clusters, earning exactly three stone and two wood. No resources are granted
   by the fixture.
4. The existing crafting UI consumes those resources for a pickaxe at full
   durability. Moving it to the toolbelt and equipping it enables a normal
   attack, which incurs wear 1. Its inventory snapshot restores exactly.

This verifies existing recipes and native inventory behavior together, and fixes
two guidance messages; it introduces no new recipes or balance changes. The
fixture positions the camera/player at generated resources rather than walking
between them. The toolbelt transfer uses the native operation, not mouse drag
automation. Snapshot restoration is in-process; this is not fresh-process save
coverage, a human playtest or a sustained-performance result. The world is
temporary; the inherited save check is a no-op, and human saves are untouched.
