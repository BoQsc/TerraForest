# Unrequested mouse capture

- Status: Corrected / scoped checks; desktop playtest review pending.
- Updated: 2026-10-28.
- Cause: finishing loading requested captured mode without player input; focus loss
  left that mode active. Captured mode inherently centres the system pointer.
- Gameplay now captures only after a focused, unhandled left click in the world.
  Loading and focus loss revoke capture; returning focus does not reclaim it.
  The first click is consumed, not an attack. Closing a gameplay menu still resumes
  an already authorized session. Background viewports cannot change global modes.
- No mouse warps, extra windows, launcher policy files or helper processes added.
- `tests/loading_mouse_ownership.gd`: 13 passing headless checks;
  `reports/checks/20261028T070529313843Z/`. The earlier headless run retained four
  assumptions about captured mode/native windows unsupported by that display driver.
- No screenshot establishes desktop input ownership. Still review actual launch,
  loading, Alt-Tab and click-to-resume on the player's desktop.
