# Example door pack

This optional pack adds `example/doors/narrow_right/v1` without gameplay code.
It reuses the existing door mesh at 0.8 width; no replacement GLB is supplied.

In `user://mods/enabled.cfg`, add or merge:

```ini
[objects]
manifests=PackedStringArray("res://mods/example_doors/example.objects.json")
```

Restart, then select **Narrow right-hinged door** from the object construction
catalog. It costs five wood, salvages two, has 75 health, opens from the right
hinge, and does not authorize zombie attacks. Existing wooden doors remain as-is.

The JSON is original CC0-1.0 authoring data. See
[provenance](../../addons/structures/objects/PROVENANCE.md) and the complete
[door content guide](../../docs/DOOR_CONTENT.md), including GLB replacements,
definition fields, limits and save compatibility.
