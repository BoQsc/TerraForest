# Pickaxe upper-right to lower-left candidate

Separate and unapproved. The ordinary accepted default is unchanged.

The user requested a more diagonal holding pose and right-to-left strike, then
rejected the first candidate and clarified **upper right → lower left**. The
second revision kept the shaft slanted through contact but was not accepted in
the playtest: the user wanted the hold higher and the strike toward the cursor.
That raised version (`bf81f85e`) was rejected for a central foreground hand,
right-heavy framing and a sliding feel. The rotational revision (`13c87bca`)
was also rejected: its head turned end-on and read as striking with the middle
while sweeping sideways. The current version drives pitch in a diagonal forward
working plane. The pointed end leads forward-left into the upper-center target
area; the socket and broad back stay visibly behind/right. The ready pose is
preserved, with the supporting hand below view. This is still unapproved.

Original R11 rest rig, static fitted finger closure and fixed hand stations;
new pose table, torso movement and strike trajectory. 120 Hz baked keys, 1.6 s
swing, contact at frame 84 (0.7 s). Idle/walk/run/jump/crouch preserve the hold.
Fixed stations are -28 cm and 0 cm along the shaft. No sliding or releasing
either grip. Native player movement owns locomotion.
The right closed hand is seated 30 degrees around the shaft for the raised
hold; that grip rotation is fixed for every clip and frame.

Author with `tools/author_pickaxe_crosscut.py` against the original
`addons/characters/Human_R11_Complete_Repost/Human.r11.blend`, then import with
`tools/import_pickaxe_crosscut.gd`. `-- --probe` prints selected anatomical
samples without generating assets. The pose table uses 60 Hz frame labels;
the action bake doubles those labels to 120 Hz.
Left upper-arm roll follows the solved forearm across the actual elbow bend,
avoiding the singularity of referencing a raised cross-body arm to its rest
direction. Both limb segments retain a consistent roll across the elbow.

Only `addons/characters/experiments/pickaxe_crosscut_tools.gd` selects the
candidate. The explicit temporary launcher is `tools/playtest_pickaxe_crosscut.gd`;
F6 switches the candidate/default for comparison without changing a setting.

Rejected and revised images, previews, checks and remaining review:
[study record](../../../issues/pickaxe-crosscut/README.md).
