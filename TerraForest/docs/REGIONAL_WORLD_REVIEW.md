# Integrated regional world review

Run `Play Regional World Review.cmd`. It opens `regional_world_review_v1`, a
separate editable copy of the prepared profile-12 world. Repeated launches preserve
your review progress. Existing gameplay worlds and the prepared source are retained.
The viewport is 1920x1080 fullscreen, capped at 60 FPS. Frame spikes remain unresolved;
this is a development review, not a performance-qualified release.

Open **Esc > World** for ten generated destinations. Gameplay shows the directory;
**Esc > Session > Enter development** enables the travel buttons. Travel uses the
normal destination loading/collision path. Exit a vehicle before using it.

The prepared world contains seventeen buildings across five settlement sites,
four regional arterial roads, a mine owned by the eastern site, a cottage cellar
near the western site, one roughly 126 m lake and three ponds. At the western
site, the cellar cottage is about 20 m east and 20 m south of the district centre.
The mine has a road/yard connection; it is not an ambient cave network.

These are initial locations, not finished cities or a complete exploration game.
Further work should improve the actual locations and travel between them. Water
flow, food/vitals and multiplayer implementation remain deferred.

On a fresh installation without the prepared save:
`python tools/prepare_combined_world.py --layout lakes --destination regional_lake_20261018`
Then use the review launcher. This cold preparation can take minutes; it is not
repeated on normal launch.

Validation: metadata test and a 22.4 s integrated menu/arrival check passed.
Gameplay had no travel buttons; development had ten; the west button loaded the
expected ground position. See evidence/world_destinations. Directory labels identify
generated sites; edited/deleted buildings are not reconstructed by opening the menu.
