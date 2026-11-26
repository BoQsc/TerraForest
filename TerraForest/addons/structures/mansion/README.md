# Homestead Manor R2

A separate two-storey courtyard mansion in the normal **Building → Prefabs**
selection. It contains every object from Homestead 01–10, repeated furnishings,
and an Outdoor 01 service yard: 265 model attachments and 5,280 editable native
cells. The main building spans 39 × 31 m; paths and yard extend the placement
envelope. Choose a clear supported site using the normal placement checks.

The ground floor groups kitchen/pantry, dining, reception/stair hall, study,
garden salon, laundry/utility and workshop around a courtyard. Upstairs are the
principal bedroom, bathroom, dressing room, guest suites, sitting room and a
courtyard balcony. Timber floors, plaster/limestone walls and thin slate roofs
reuse existing material assets. The stair has a three-metre-wide flight.

`author.gd` is the editable offline recipe; `homestead_manor.tres` is the runtime
native prefab. `catalog.gd` exposes it without executing the author. Object ids
and model keys remain those of the original packs. Doors/windows and each fabric
cell retain existing individual interaction and removal behavior.

From `TerraForest`, inspect through the admitted runner:

```text
python tools/run_godot_check.py homestead_mansion --isolated-render --require failures=0 --timeout 120
```

Add `-- --author-mansion --check-layout` to rebake and verify. Run
`tools/object_content_provenance.py` after intentional author/model changes.
The test checks all 100 identities, strict compound placement, exact restoration,
independent cell removal, furnishing support and the main stair up/down, then
captures six views. It does not certify every doorway or a generated terrain lot.

This is an additional design awaiting user review, not a generator default.
Review history, evidence and remaining acceptance:
[Object pack integration](../../../docs/OBJECT_PACK_INTEGRATION.md) and
[visual tracker](../../../issues/homestead-manor/README.md).
