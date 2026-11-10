# Temporary pistol feel controls

Status: installed; implementation and scoped packaged checks pass.
User visual/feel review and foreground FPS qualification remain open.

Esc → Pistol trial contains seven independent, default-on switches: walking bob,
turn/movement sway, dynamic crosshair with confirmed-hit marker, physical hit
reactions, hit animations, blood splash and increased limb dismemberment. The
existing original-recording sound switch is on this page too. Disable-all and
restore-defaults buttons support immediate comparison. Preferences are stored in
`user://pistol_trial.cfg`; offscreen checks cannot overwrite player preferences.

The trial adapter is `addons/player_runtime/pistol_trial.gd`. Motion composes
bounded presentation offsets with the existing recoil/landing layer; it never
changes the eye camera, projectile direction, movement motor or authored paired
animation clock. ADS reduces motion to 15%; stationary bob decays away. Switching
items, pausing, entering a vehicle or disabling motion clears its state. It does
not keep the player-view loop awake when all applicable presentation is idle.

The reticle stays centered on the aim ray. Its expansion is presentation feedback,
not a new spread mechanic. Hit marks require an accepted zombie hit. Disabling it
restores the ordinary crosshair while respecting vehicle visibility.

Hit reactions reuse the existing native joint springs over authored animation,
not a second rigid-body integrator. Native angular bounds, recovery, attack/stagger
cooldowns, collision readiness and corpse physics are unchanged. Individual
response switches apply only to pistol hits; other weapons keep their behavior.
The projectile retains its weapon identity across equipment changes.

Blood uses twelve existing GPU particles with a short 0.4 s lifetime, including
the existing mist appearance. No new texture, shader, decal, simulation loop or
emitter pool is introduced. The global impact-effects switch still takes
precedence. The eight-emitter / 48-particle-per-emitter caps remain unchanged;
saturation drops presentation only, never damage.

Increased dismemberment adds a 20% chance on accepted arm/leg hits, using a separate
random stream from weapon spread. Head and torso are excluded. Ordinary limb
durability still applies; switching the option off removes the extra chance.
Severing goes through the existing authoritative anatomy and save path. Damage,
magazine size, firing cadence, projectile cap and ammunition rules are unchanged.

## Evidence and limitations

Paths are relative to the project. No new saved world or worktree was created.

- `reports/checks/20261110T150244463278Z_pistol_package`: final package passes
  32 trial checks, 72 handgun checks and 36 actual-world firearm checks using the
  installed native libraries. Live disabled blood/reaction switches preserve
  accepted projectile damage. The actual installed executable passes startup
  smoke only. Installed PCK SHA-256:
  `28e8cfc84187e5065dc22f66327ab6b2337c60bd8f849b728cbd97fb66dfd4b0`.
  `previous_package.archive.json` hash-verifies the predecessor; `installed.json`
  records unchanged native DLLs and removed staging. Water settling remains off.
  The first candidate and its rejected packaged-driver report remain archived:
  a headless test attempted to create `res://reports` inside the read-only PCK;
  its 33 gameplay assertions passed, but that run was not accepted. The driver
  now creates image output only for rendered runs and accepts an explicit path.
- `reports/checks/20261110T150134524424Z`: 31 trial checks pass, including live
  toggles, preference reload, exact removal of motion, native spring/animation
  response, authoritative severing and bounded blood emission; clean shutdown.
- `reports/checks/20261110T150025261366Z`: 33 actual-world firearm checks pass,
  including an actual pistol projectile hitting a resident zombie, one damage/
  blood/audio event, no floating bullet hole, bounded pools and clean shutdown.
- PX9 paired animation/magazine regression: `20261110T150045676523Z`; existing
  player feel: `20261110T150101652318Z`; native anatomy: `20261110T150158430992Z`;
  effect resources: `20261110T150220230026Z`. All pass.
- Universal drop and physical-drop checks pass in `20261110T145318830700Z` and
  `20261110T145331450158Z`; combat state passes in `20261110T145305767842Z`.
- Offscreen rendered review: `reports/checks/20261110T150147129576Z_pistol_review`.
  `pistol_idle.png`, `pistol_hit.png`, `pistol_aim.png` and `pistol_options.png`
  show the actual paired model, native zombie, GPU blood and controls. Studio
  fixture images were inspected; they are not normal-world visual acceptance or
  frame-rate evidence. Earlier compact-blood comparison remains in
  `20261110T145413261460Z_pistol_review`.

Retained rejected checks: `20261110T145035535953Z` caught a UI signal reference
cycle (fixed; subsequent runs exit cleanly); `20261110T145345994075Z` caught
crosshair lookup before HUD construction (fixed by binding at the first tick).
The synthetic G-key world check still fails its two drop assertions on candidate
(`20261110T145749689895Z`) and unchanged installed baseline
(`20261110T145924491361Z_drop_baseline`). Do not count this as a passing input gate.
The driver now exits cleanly on an empty pickup result rather than indexing it
and timing out. No runtime input restriction was relaxed to make it pass.

Return to foreground movement/turning/ADS/reload/rapid-hit comparisons when the
user resumes foreground tests. Check whole-frame tails and GPU work as well as
visual preference. The stable 60 FPS/headroom milestone remains unqualified.

## Removal

For playtest rollback, use Disable all on the trial page. For source removal,
revert the focused trial commit: its adapters and integration hooks are isolated;
no world/save-format migration is required. Original project assets and native
systems are reused with their existing provenance. New original adapter/test
code is 0BSD; no external material was imported.
