# Approved default and grouped settings

User explicitly approved the measured improvement as the default and requested
that related controls be grouped, with toggles enabled. New worlds now use native
footprint road planning (`road_grid=3`, binary recipe v4). The selector reads this
value from the shared recipe default instead of maintaining another literal.

Terrain and Roads & shoulders are both checked in one Building-grid fit group
under Create world / Landscape. The existing placement preference has a matching
group in ESC, with directions to the creation settings. No new toggle, algorithm,
per-placement terrain correction, or saved-world migration is introduced. Existing
player placement preferences remain respected.

The default production generation/save/reload check passes all 32 checks, including
the matching session group, persisted v4 recipe, exact approved house blocks and
one native window. The separate test world is `recipe_generated_e83d7f5db1c6d3c1`.
UI checks cover expanded towns, launch options, both checked controls in the same
group, preview cache invalidation and scrolling at 1920×1080 and 1280×720.
Legacy recipe restoration and independent toggle behavior also pass.
Pack export and startup smoke pass with all fourteen native libraries. The
1280×720 grouped-settings capture was inspected; both checked controls are
reachable together by scrolling the existing Landscape panel.

This is approval to use an incremental improvement, not a declaration that all
gap/burial cases are solved. The original shoulder failure and 30.12 cm result
remain documented in the parent evidence; their diagnostic limits are unchanged.
