# Vehicle Driving Test

Run `Launch Vehicle Demo.cmd` in the TerraForest project directory. It imports
assets and runs this isolated scene at 1920x1080 fullscreen Forward+, 60 FPS,
with the original 120 Hz physics. See PROVENANCE.md for the user's 0BSD grant.

The original car.gd remains a behavior reference. car_native.gd delegates
steering and longitudinal control to the vehicle_runtime C++ addon. Suspension,
impacts, damage and accessories remain scripted pending migration. This scene
does not yet integrate vehicles into the streamed world.

The ZIP intentionally contains no `.godot` cache and no generated `.import` files.
On the first run, the launcher asks Godot to perform a headless import. Godot creates
and owns `.godot` and the source-side `.import` files. Later runs reuse that cache.

If the import process exits or crashes, the launcher stops and reports the real exit
code instead of trying to run the game with an incomplete cache.

Telemetry is off by default. F6 starts `DRIVE_TRACE.csv`; F7 stops it.


Launcher fix: first-run headless import exit status is read with delayed expansion, so a successful import continues to the game and a real crash is reported correctly.
