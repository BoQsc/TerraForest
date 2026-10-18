# Ore headlamp response — 2026-10-18

The preceding `regional_ore_gameplay` captures show a strong white highlight
over newly excavated iron/copper. Both materials previously used metallic 0.55
and roughness 0.65. Natural ore now uses metallic 0.15 and roughness 0.85.
Constructed metal keeps its existing response; vein positions, quantities,
material colors, textures, light range and energy are unchanged.

The terrain's custom light function uses METALLIC for direct highlight intensity.
Reducing that value softens the highlight; changing ROUGHNESS alone would not
change the custom highlight exponent. No new texture reads, shader branches,
passes, lights or geometry were added.

Reran `regional_ore_gameplay.gd` in read-only `generated_world_v4`, fullscreen
1920×1080. PASS in 25.02 seconds with no reported engine diagnostics. Both ore
removal/reward checks, tool wear and direct inventory delivery still pass.
Inspected both captures against the preceding evidence: ore grain is clearer
and the bright excavation-edge highlight is weaker. The cave remains dark away
from the lamp. This does not qualify visual discoverability throughout the mine
or sustained performance. The iron HUD's 60 FPS is not a performance benchmark.
