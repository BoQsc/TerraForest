# Integrated world generation

Create a new prepared world with a chosen seed:

```powershell
python tools/prepare_combined_world.py --layout districts --seed 42 --destination my_world_42
```

This generates profile-12 terrain, regional roads, five furnished settlement sites,
entrance paths, a western cellar, the eastern mine, four lakes and two central
patrol residents. Terrain generation and runtime representation remain native;
the preparation script coordinates existing addon authoring operations offline.
The regional topology and prefab palette are currently fixed; a different seed
changes terrain/layout parameters and central prefab choices, not the entire
settlement design vocabulary. This is not a finished procedural-city generator.

The tool bakes a staging world, saves, reopens in a fresh process, compares building,
road, furnishing and resident state, and checks restored seed/generator identity.
Only a passing preparation is copied to the named destination. Existing destination
saves are never overwritten, even when a different seed is supplied. Use a new
name to generate a new world. Failures retain logs in reports/combined_preparation.
Cold preparation can take minutes; normal launches load the prepared save.

Open the generated world for gameplay:

```powershell
python tools/run.py --slot my_world_42 --generator 12 --ground-cover --actors --vehicle-fleet --gameplay-construction
```

The launcher uses 1920x1080 fullscreen with a 60 FPS cap. Saved seed/generator
identity takes precedence over launch defaults. These commands do not replace the
existing regional review worlds. Esc > World lists generated destinations; travel
buttons are available only in development mode.

Supported seed range: 0 through 2147483647. Passing preparation is not a guarantee
of all-seed terrain suitability, continuous-travel performance or long-run thermal
behavior. Those require separate checks of the actual generated world.
