# Preserve approved frame pacing

Status: limiter-policy experiment rejected and reverted, 2026-11-10 (Europe/Kiev).
Stable 60 FPS with headroom remains unresolved.

The user reaffirmed the existing approved foreground cap, VSync and background
cap. Performance work must reduce world/player/rendering costs with that policy
intact. Do not substitute a change to those limits for fixing stalls. Uncapped
diagnostic captures measure capacity only; they do not qualify normal gameplay.

An uncommitted experiment would have removed the software cap when the reported
display refresh matched it. It also changed the dialog test expectations. Both
changes and their dedicated policy test were reverted; controller startup again
assigns `Engine.max_fps = max_fps`. The diagnostic pacing-switch option was removed.
No export or installation contained that change. The installed PCK still hashes
to `acccce4d9b176cc7c23a559116eda4672e7917039263d0ba55bdd9c45b77c7be`.

The earlier claim that the limiter comparison established a concrete cause was
too strong. Eight-second stationary phases with unchanged world activity showed
different frame distributions, but did not isolate the remaining stalls or
establish gameplay nonregression. Retain the experiment at
`reports/performance_changes/20261109T215404462427Z_frame_pacing_abba`; do not use
it as authorization or acceptance for a pacing-policy change.

Other evidence from this investigation:

- `20261109T214651201184Z_regression_current`: current-source world still reaches
  27.453 ms, including 25.801 ms drawing with 6.475 ms reported GPU time. Drawing
  contains work and waits; this is not proof of one rendering or driver cause.
- `20261109T214847504739Z_player_feel_abba`: grounded idle/turning on-off-off-on
  control does not support the new player feel as the main regression cause.
- `20261109T215117560533Z_rendering_separate_probe`: rejected. Synchronous timer
  queries contaminated performance; image readback errors, render-thread shutdown
  error and two leaked objects rule out adopting the separate-render-thread mode.
- `20261109T215923162277Z_pacing_hud_candidate`: save/destruction/shutdown pass,
  but this is an uncapped diagnostic, not a pacing-policy acceptance. The hidden
  developer-HUD guard remains an uncommitted candidate, not a verified FPS fix.
- `reports/checks/20261109T215310595350Z`: world-browser suite fails nine existing
  generator-ID expectations (23/22/19/17 versus current 29/28/31/30). The diagnostic
  save exclusion assertions pass. Do not report the full browser suite as passing.
- `reports/checks/20261109T215921586900Z`: world-presentation checks, including
  explicit access and unchanged bytes for excluded diagnostic saves, pass.
- `20261109T220138815419Z_approved_policy_source`: after restoring the approved
  policy, every sampled gameplay phase retains software cap 60 and VSync enabled.
  Normal save, three-barrel destruction and shutdown pass without error/leak
  diagnostics. Outdoor sweep still reaches 37.649 ms; this is not a stable-FPS
  pass. Sampled process memory reaches the provisional 4.02 GiB warning band.

Return gate: repeat actual gameplay with approved cap/VSync, validate remaining
draft changes independently, compare complete frame distributions and resource
growth, inspect relevant visuals, and verify the eventual installed package.
Do not claim stable 60 FPS or general nonregression before these gates pass.
