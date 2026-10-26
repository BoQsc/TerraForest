# Pickaxe upper-right to lower-left candidate

Separate and unapproved. The ordinary accepted default is unchanged.

The user requested a more diagonal holding pose and right-to-left strike, then
rejected the first candidate and clarified **upper right → lower left**. The
revision keeps the shaft slanted through contact and follows down and left.

Original R11 rest rig, static fitted finger closure and fixed hand stations;
new pose table, torso movement and strike trajectory. 120 Hz baked keys, 1.6 s
swing, contact at frame 84 (0.7 s). Idle/walk/run/jump/crouch preserve the hold.
No sliding or releasing either grip. Native player movement owns locomotion.

Author with `tools/author_pickaxe_crosscut.py` against the original
`addons/characters/Human_R11_Complete_Repost/Human.r11.blend`, then import with
`tools/import_pickaxe_crosscut.gd`. `-- --probe` prints selected anatomical
samples without generating assets. The pose table uses 60 Hz frame labels;
the action bake doubles those labels to 120 Hz.

Only `addons/characters/experiments/pickaxe_crosscut_tools.gd` selects the
candidate. The explicit temporary launcher is `tools/playtest_pickaxe_crosscut.gd`;
F6 switches the candidate/default for comparison without changing a setting.

Rejected and revised images, previews, checks and remaining review:
[study record](../../../issues/pickaxe-crosscut/README.md).
