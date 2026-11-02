# Responsive world entry

The selector acknowledges Play before loading the game. One persistent
`world_session.gd` keeps the same window and presents the loading cover until
initialization completes. Duplicate Play requests are ignored. Generation's
94% handoff and elapsed time carry into loading rather than starting over.

`startup_resources.gd` loads only the requested dependency graph. Non-script
resources use Godot's threaded resource loader; GDScript dependency groups load
on the scene thread, yielding between groups with an 8 ms soft budget. A single
engine call is not preemptible. The index is built ahead of time, not by scanning
source files during loading. Resources stay referenced until their consumer
is constructed. No background thread instantiates the game or modifies its tree.

Regenerate the original 0BSD dependency index after changing literal `preload`
or quoted `extends` dependencies:

```text
python tools/build_startup_index.py
python tools/build_startup_index.py --check
```

Export checks freshness. Dynamic loads and external mod entry points retain their
existing behavior; this index is not a new mod restriction or a complete asset
manifest. Each root is limited to its own graph. Cycles are visited once.

World initialization yields between real setup stages, keeping the incomplete
world's processing disabled. The scene host and generation task explicitly wait
for `startup_complete`; palette setup finishes before deferred docking. Forest
assets build on a private, joined worker, with renderer/node attachment on the
owner thread. CLI review scenes without a session host retain synchronous setup.

Generation cancellation during resource preparation does not start a world and
does not replace its owning session's arguments. An active resource request is
consumed before cancellation returns. Native generation/publishing workers and
gameplay scheduling are otherwise unchanged. No frame-cap or power-mode change.

Rejected trials: threading the whole script graph leaked native RefCounted
objects; warming every individual GDScript also produced shutdown retention.
Retain grouped owner-thread script loading, not those trials. See the
[browser tracker](../issues/browser-responsiveness/README.md) for evidence and
remaining single-call costs. API reference: [Godot background loading](https://docs.godotengine.org/en/4.4/tutorials/io/background_loading.html).
