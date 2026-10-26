# Named gathering prompts and interaction priority

2026-10-26 policy update: [quiet interaction hints](../../../issues/world-interaction-hints/README.md).
Common foliage no longer displays an automatic label; stones/flowers remain, and
bushes require harvesting. The text below records the earlier implementation.

2026-10-15. The shared world interaction adapter now identifies ground-cover
species with the existing native picker. Its 10 Hz presentation query reuses
the building scene ray, clipped to gathering's 2.5 m reach. It does not scan
resident instance arrays or mutate inventory/removal records. Collection and
presentation share the readiness, obstruction and native picking probe.

Directly aimed gathering now precedes proximity-based vehicle entry. Rejected
collection consumes that interaction and displays its reason, rather than
silently attempting to enter a nearby vehicle or collect a different pickup.

`ground_interaction_hint` passed in the actual temporary world with ground
cover and gameplay enabled at 1920x1080 fullscreen, capped at 60 FPS. It checks
species text, unchanged durable state during preview, reach clipping, dirty
owner rejection, full-inventory target preservation, action priority and exact
reward quantity. Vehicle entry is replaced by a synchronous counting probe only
during the E calls; this tests dispatch priority, not driving behavior. No human
save is loaded or written; the inherited test's save step is temporary/no-op.

The graphical `building_interaction_hint` regression also passed. An initial
headless invocation failed its mouse-capture-dependent assertions; that mode
cannot qualify this graphical fixture and its log is retained. No performance
or thermal improvement is claimed. Ground-cover population scale is unchanged.
