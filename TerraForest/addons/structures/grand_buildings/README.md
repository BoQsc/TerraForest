# Three grand buildings, revision 1

Additional designs in ordinary **Building → Prefab** selection:

| Design | Main footprint | Occupied levels | Interior |
| --- | --- | --- | --- |
| Foundry Court | 69 × 45 m, plus exterior fire stair | Five residential floors and accessible roof | 60 flats with living/kitchen, bedroom and separate bathroom; shared corridors and two stair cores |
| Saint Brigid | 105 × 81 m cruciform plan, plus approach | Two basement floors, nave, two galleries, 13 bell-tower landings | Deep crypt, undercroft, open nave, transepts, sanctuary, archive shelving and twin bell towers |
| Needle Street | 55 × 47 m podium; upper floors set back | Ten occupied floors and accessible roof | Eight street shops/workrooms, 58 flats, balconies and a continuous stair core |

The baseline mansion's main mass is 39 × 31 m, with two storeys. The dedicated
regression independently measures supported columns with two metres of headroom;
each addition must exceed twice the mansion's measured clear floor area. The
cathedral must also exceed twice the mansion's full bounds in **all three axes**,
including the mansion's paths and outdoor furnishings. Captured engineering
measurements and review status are linked in the [visual tracker](../../../issues/grand-buildings/README.md).

All fabric remains individually editable native building cells. Doors keep their
ordinary 2 m height. Existing Homestead furniture, E2 finishes, doors and windows
retain their own assets and notices. `author.gd` is an offline recipe;
`catalog.gd` loads the baked `.tres` resources during play. The cathedral's
`site_surface_offset=9` locates its main threshold above two cellar floors;
placing it in terrain requires a surveyed, excavated site of that scale.

From `TerraForest`:

```text
python tools/run_godot_check.py grand_buildings --require failures=0 --timeout 420
python tools/run_godot_check.py grand_buildings --isolated-render --require failures=0 --timeout 420 -- --no-walk
python tools/run_godot_check.py grand_buildings_world --require failures=0 --timeout 180
```

Rebake with `-- --author-buildings`; `--bake-only` omits runtime checks. Restrict
iteration with `--building=grand_cathedral` (or either other catalog ID).
`--restore-from=<receipt directory>` checks all recorded native snapshots in a
fresh process. Refresh and verify `tools/grand_building_provenance.py` after
intentional author/test/input changes. New original arrangement data is CC0-1.0;
new code is 0BSD, as stated in the adjacent notice.

These are additional construction designs awaiting user visual review. They do
not replace existing buildings, migrate saves, or become settlement generation
defaults. Terrain-fit review and crowded-street performance need a separately
selected populated site; isolated checks do not certify those outcomes.

The additional **Metropolis & inhabited region** starting recipe now provides
that separately selected source-world integration. See its [recipe contract and
generated-site evidence](../../../docs/METROPOLIS_REGION.md). Existing starting
recipes and saved buildings are not replaced.

The cathedral's mostly empty bounding volume exceeds the existing 262,144-cell
corner-selection capture volume. Its sparse authored prefab stays within the
native occupied-cell budget and is reusable from the catalog; whole-building
recapture through the corner tool is not qualified. No capture limit was raised.
