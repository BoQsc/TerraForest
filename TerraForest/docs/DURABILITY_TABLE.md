# World durability table

Initial inventory of current rules, 2026-10-23. These are existing gameplay values,
not a completed balance pass. The shared definitions are in
`addons/player_runtime/durability_catalog.gd`. Native stores own accumulated damage,
wear and persistence. Player attacks and zombie attacks on wooden doors read the
same model profile. Player inventory and dropped-tool schemas share tool maxima.

## Terrain, blocks and vegetation

| World thing | Maximum | Unit / rule |
| --- | ---: | --- |
| Terrain: topsoil, rock, ore, asphalt roads | 30 | Per targeted one-metre cell; excavation uses the existing brush |
| Brick block | 90 | Per occupied cell |
| Wood block | 60 | Per occupied cell |
| Concrete block | 120 | Per occupied cell |
| Metal block | 180 | Per occupied cell |
| Tree, all current tree variants | 90 | Per tree identity |
| Small stone | 45 | Per ground-cover identity |
| Fern | 10 | Per ground-cover identity |
| Grass clump | 10 | Per ground-cover identity |
| White wildflower | 10 | Per ground-cover identity |
| Golden wildflower | 10 | Per ground-cover identity |
| Violet wildflower | 10 | Per ground-cover identity |
| Low bush | 40 | Per ground-cover identity |
| Dry twigs | 10 | Per ground-cover identity |
| Woody bush | 2 | Exactly one damage per accepted hit: two hits |

Cubes, stairs, slopes, spheres and other building shapes use their block's
material maximum. Houses, towers, bridges, basements and other POIs are assemblies
of these blocks and model placements; they do not have one aggregate health pool.
Terrain materials currently share one hardness value. Ground-cover collection
with E is separate from damage and can collect an undamaged plant directly.

## Placed models

| Asset identity | Name | Maximum | Tool damage group |
| --- | --- | ---: | --- |
| `furniture/table/v1` | Wooden table | 90 | Wood |
| `furniture/chair/v1` | Wooden chair | 90 | Wood |
| `furniture/shelf/v1` | Wooden shelf | 90 | Wood |
| `storage/wooden_chest/v1` | Wooden chest | 90 | Wood |
| `architecture/wooden_door/v1` | Wooden door | 90 | Wood |
| `architecture/wooden_window/v1` | Wooden window | 90 | Wood |
| `architecture/wooden_ladder/v1` | Wooden ladder | 90 | Wood |
| `architecture/wooden_fence/v1` | Wooden fence | 90 | Wood |
| `architecture/metal_beam/v1` | Metal beam | 90 | Other |
| `architecture/doorway/v1` | Doorway | 90 | Other |
| `architecture/metal_guardrail/v1` | Metal guardrail | 90 | Other |
| `architecture/metal_stairrail/v1` | Metal stair rail | 90 | Other |
| `architecture/concrete_paving/v1` | Concrete paving | 90 default profile | No separate hit collider; hits reach its supporting terrain |

Nonempty chests are protected from damage/destruction. Windows are one placement,
without separate glass health. These shared model values and damage groups are
provisional; metal models currently retain the same maximum as wooden furniture.
Unknown modded model keys retain the existing 90-point fallback, classified as
wood if their key contains `wood`, `furniture` or `storage`, otherwise other.

## Entities and carried tools

| Thing | Maximum | Rule |
| --- | ---: | --- |
| Settlement actor | 100 | Per persistent actor identity |
| Vehicle | 300 | Per persistent vehicle identity |
| Pickaxe | 200 | One wear per accepted hit |
| Hatchet | 200 | One wear per accepted hit |
| Building hammer | 200 | One wear per accepted hit |
| Assembly tool | 200 | One wear per accepted hit |

Zombie anatomy remains owned by `addons/characters/runtime/zombie.gd` (`PARTS`),
so the standalone character addon does not depend on player-runtime balance data.
The HUD reads the live hit region. Current anatomy values are:

| Zombie health / region | Maximum |
| --- | ---: |
| Overall health and torso | 180 each |
| Head | 50 |
| Upper arm, each side | 50 |
| Forearm, each side | 38 |
| Hand, each side | 24 |
| Thigh, each side | 65 |
| Shin, each side | 52 |
| Foot, each side | 32 |

Torso hits debit overall health in full; other hits debit it at 15% unless the
hit severs the region, which follows the existing anatomy rules. Dismemberment
and death are not new systems introduced by this table.

## Explicit gaps and tuning policy

Water is scoop/place data, without durability. Dropped resources, buckets, clothing
and empty hands do not currently have a destructible world-health profile. The
player's zombie damage receiver records damage but has no finite health/death
system. Asphalt roads use terrain durability rather than a separate health pool.
Concrete paving lacks independent hit collision; its supporting terrain can be
excavated. The missing profiles are unsupported states, not infinite durability
values or completed damage coverage.

The catalog coverage check lists any registered model missing an explicit row.
New material, species, model and durable-tool definitions must update this table.
Keep maxima unchanged until a deliberate balance pass: the current native damage
store resets a target's accumulated damage when supplied a different maximum.
Changing maxima therefore needs a saved-world migration decision. This initial
catalog preserves all existing maxima and snapshot formats.

A successful fatal player hit hides the near-crosshair durability display
synchronously. Surviving targets retain the existing 2.2-second feedback timeout.
