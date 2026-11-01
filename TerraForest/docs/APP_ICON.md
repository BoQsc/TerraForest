# Application icon

Windows takes the icon it shows in Explorer, the taskbar and alt-tab from the
executable's PE `.rsrc` resources. Godot writes none of that from
`project.godot`; the export template ships Godot's own icon, so the icon has to
be replaced in the built binary.

## Files

Everything lives in `steam/app_icon/`:

| Path | Role |
| --- | --- |
| `terraforest.ico` | The icon, 256/128/64/48/32/24/16 px. |
| `make_app_icon.py` | Regenerates that `.ico` from code (needs Pillow). |
| `set_app_icon.py` | Installs the `.ico` into an executable, or verifies it. |

The folder carries `.gdignore`, so Godot neither imports the `.ico` nor copies
it into exports. `tools/` is outside the project's export filters.

## Use

```bat
python steam/app_icon/make_app_icon.py --preview   :: rewrite the .ico (and a 256 px PNG)
python steam/app_icon/set_app_icon.py              :: patch the project executable
python steam/app_icon/set_app_icon.py --check      :: verify without writing
python steam/app_icon/set_app_icon.py --exe dist\TerraForest.exe
```

The icon defaults to the copy beside the script, and the executable defaults to
the first existing of `TerraForest.exe`, `Godot Engine TerraForest.exe`,
`dist\TerraForest.exe`, found from the script's own location - so the command
works from any working directory. Only `set_app_icon.py` is needed to patch a
build; `make_app_icon.py` is needed only to change the artwork.

## What the patch does and does not touch

It rebuilds the existing `.rsrc` payload: the icon bitmaps and the
`GODOT_ICON` group come from the `.ico`; `RT_VERSION` and `RT_MANIFEST` are
copied byte for byte with their type/name/language keys. No section table entry,
RVA, `SizeOfImage`, file length or trailing data changes, the icon group keeps
its original name, and re-running the patch is idempotent. `--check` also
validates the directory ordering the loader's binary search depends on.

The alternative - appending a new `.rsrc` section holding only the icons, as
most post-link icon tools do - silently drops `RT_MANIFEST`, which costs the
process its DPI awareness and comctl32 v6 visual styles, and drops
`RT_VERSION`.

## Limits

- A re-export writes a fresh template binary with Godot's icon again. Re-run
  `steam/app_icon/set_app_icon.py --exe <export>` after exporting, or set the
  preset's application icon once the project has an imported icon resource.
- Explorer caches the icon per path. After a patch, an already-open window can
  keep drawing the old icon; renaming the file or refreshing the view shows the
  new one. `python steam/app_icon/set_app_icon.py --check` is the honest test of
  the binary itself.

## Licensing

The tool code is 0BSD, like the rest of `tools/`. The icon is original CC0-1.0
artwork drawn by `steam/app_icon/make_app_icon.py`; it contains no Godot logo,
so it adds no attribution requirement beyond the project's existing inventory.
Godot's own default icon, replaced here, is part of the exported engine binary.
