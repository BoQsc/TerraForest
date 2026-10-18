# Current integrated world promoted to the main launchers

Prepare Generated World.cmd now selects districts and generated_world_v4. Play
Generated World.cmd opens that named save with ground cover, actors, fleet and
gameplay enabled at 1920x1080 fullscreen/cap 60. The world browser supports the
same content through its integrated preset. Existing older named saves remain.

The verified regional_transport_20261018 source was cloned once without overwrite
to generated_world_v4. Source and destination canonical hashes match after checking:
1152d838dcd1c4491f6403b6f998f3c764aa2b9f9179819661ae567ee82e2468.
Invoking the actual Prepare command afterwards returned successfully without
regeneration. The actual Play command's --dry-run output was parsed, its scene
argument replaced with regional_transport.gd and snapshot-readonly appended for
the automated check; all other launch settings were retained. Both saved cars
restored, activated, accepted E entry, drove, braked and accepted E exit. Passed
in 32.39 seconds. The test did not save its changes.

The named launcher reports generator 1 as its unused new-world fallback; it refuses
a missing named save, and the existing save restores its own profile-12 identity.
This change promotes integrated content, not performance qualification or completed
large cities. Older checkpoint launchers still intentionally open separate saves.
