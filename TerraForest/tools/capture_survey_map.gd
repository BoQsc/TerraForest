# SPDX-License-Identifier: 0BSD
extends SceneTree
## Capture the real LIVE REGIONAL SURVEY map with the game's own planner:
## world_generation_plan.preview(). The frontier recipe does not fit every
## terrain, so seeds and landscapes are searched exactly like the browser does;
## the first fitting plan is written as a square PNG for the create-world mockup.

const OUT := "res://demo/world_survey/assets/survey_map.png"
const FRONTIER := {
	"biome": 0,
	"settlements": 2,
	"districts": 1,
	"network": 2,
	"trails": 2,
	"road_grid": 3,
	"material_veins": 1,
	"introduction": 1,
}
const GENERATORS := [29, 17, 20, 21]


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var host := Node.new()
	root.add_child(host)
	var startup = preload("res://addons/world_runtime/startup_resources.gd").new()
	var prepared: bool = await startup.prepare(host, "res://addons/world_runtime/world_generation_plan.gd")
	print("startup prepared: ", prepared)
	var plan = load("res://addons/world_runtime/world_generation_plan.gd")
	for generator in GENERATORS:
		for seed_value in range(1, 121):
			var result: Dictionary = plan.preview(int(seed_value), int(generator), true, true, true, "user://cartography/generation", FRONTIER, null, false)
			if not result.get("ok", false):
				continue
			var image := Image.create_from_data(256, 256, false, Image.FORMAT_RGBA8, result.pixels)
			# Drop the renderer's cyan outer ring; keep the survey's tan frame.
			image = image.get_region(Rect2i(8, 8, 240, 240))
			var target := ProjectSettings.globalize_path(OUT)
			DirAccess.make_dir_recursive_absolute(target.get_base_dir())
			var error := image.save_png(target)
			print("FOUND seed=", seed_value, " generator=", generator, " error=", error)
			print("saved ", target)
			print("buildings ", result.get("building_count"))
			print("network ", result.get("network"))
			print("options ", result.get("options"))
			quit()
			return
	print("no fitting plan found")
	quit(1)
