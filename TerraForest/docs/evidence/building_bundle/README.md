# Extracted building addon check

The structures dependency ZIP contains 102 loadable resources. Its exact file
manifest and hashes validate; cache-free extraction imports and loads successfully
on Godot 4.7.2 Windows with explicit `--import-frame-delay-ms 100`.

New `--exercise-structures` option runs a supplied test against only extracted
runtime resources. Twelve checks cover native-world preparation, door/window/rail
catalog registration and icons, real physics door collision, opening and exact
hinge/model snapshot restoration followed by closing. The fixture runs rendered
1920x1080 capped at 60 FPS; this is not a visual or performance qualification.

Reproduce with `python tools/package.py --addon structures`, then
`python tools/verify_addon_bundle.py --addon structures --godot <executable> --import-frame-delay-ms 100 --exercise-structures`.

No main-project resource fallback is available in the temporary extraction.
Only the fixture is copied from tests. The archive hash and fixture hash are in
result.json. Host gameplay adapters, standalone editor workflows, disk save,
export, default import reliability and other platforms remain unqualified.
