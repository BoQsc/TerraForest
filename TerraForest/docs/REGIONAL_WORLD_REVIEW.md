# Integrated regional world review

Run `Play Regional World Review.cmd`. It opens `regional_world_review_v18`, a
separate editable copy of the prepared generator-16 world. Repeated launches preserve
your review progress. Existing gameplay worlds and the prepared source are retained.
The viewport is 1920x1080 fullscreen, capped at 60 FPS. Frame spikes remain unresolved;
this is a development review, not a performance-qualified release.

Open **Esc > World** for ten generated destinations. Gameplay shows the directory;
**Esc > Session > Enter development** enables the travel buttons. Travel uses the
normal destination loading/collision path. Exit a vehicle before using it.

The prepared world contains twenty-three buildings across five settlement sites,
four regional arterial roads, a mine owned by the eastern site, a cottage cellar
near the western site, one roughly 126 m lake and three ponds. At the western
site, the cellar cottage is about 20 m east and 20 m south of the district centre.
The mine has a road/yard connection; it is not an ambient cave network.

These are initial locations, not finished cities or a complete exploration game.
Further work should improve the actual locations and travel between them. Water
flow, food/vitals and multiplayer implementation remain deferred.

On a fresh installation without the prepared save:
`python tools/prepare_combined_world.py --layout districts --natural --seed 42 --destination sited_region_42_20261020`
Then use the review launcher. This cold preparation can take minutes; it is not
repeated on normal launch.

Validation: metadata test and a 22.4 s integrated menu/arrival check passed.
Gameplay had no travel buttons; development had ten; the west button loaded the
expected ground position. See evidence/world_destinations. Directory labels identify
generated sites; edited/deleted buildings are not reconstructed by opening the menu.

The northern site now has four three-storey buildings; west and south have four
cottages each, while the east has two cottages beside the mine. The western cellar
cottage brings the total to 23. These reuse existing furnished prefabs. The previous
review save remains accessible with `Play Regional World Review.cmd --previous-review`.
The updated save passed fresh-process reopening and a 25.8 s district arrival/count
check with inspected north/south screenshots. See evidence/regional_districts.

Version 3 adds baked entrance paths to the 14 outer-district buildings. Use
`--review-version 2` to open the earlier district review, or `--previous-review` for v1.
