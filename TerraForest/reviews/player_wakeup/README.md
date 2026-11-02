# First-person waking motion

- User approved the five-second preview on 2026-11-02.
- Exact reviewed motion: `Human.wakeup.res`; installed copy:
  `addons/characters/runtime/assets/Human.wakeup.res`.
- 4.4 seconds: right-hand waking gesture, both hands inspecting/flexing, lower.
  Final 0.6 seconds returns to the selected item. No camera or physical root motion.
- New-world upstairs starts persist one pending bit in the existing 56-byte native
  player-pose record. Ordinary loads of played/legacy worlds do not replay waking.
- `entry_fly_in.arm_respawn()` provides the same presentation hook. The game does
  not yet have a complete player health/death/respawn lifecycle; this hook alone
  does not implement that gameplay system.
- Reproduce: Blender `Human_R11_Complete_Repost/Human.r11.blend` with
  `tools/author_player_wakeup.py`, then `tools/import_expedition_motion.gd`,
  `python tools/check_expedition_motion.py wakeup`, and the Blender encoder
  `tools/encode_wakeup_review.py` with its report folder after `--`.
- Original AI-assisted motion is CC0-1.0; preserved Human R11 rig notices apply
  to inherited meshes/rig data. See `provenance.json`. Authoring and review media
  are excluded from game exports; only the compressed animation library ships.
- Normal-speed approval evidence:
  `reports/expedition_motion/20261102T102506379981Z/Wakeup.proposal.mp4`.
