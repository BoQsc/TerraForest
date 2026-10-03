# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var terrain=preload("res://addons/volumetric_terrain/terrain_world.gd").new();root.add_child(terrain)
	terrain.backend.world_generator=2;terrain.backend.world_seed=1703;terrain.diagnostics_pause_streaming=true
	terrain.start(StandardMaterial3D.new(),true)
	var deadline:=Time.get_ticks_msec()+30000
	while not terrain.world_ready and Time.get_ticks_msec()<deadline: await process_frame
	var asset=ClassDB.instantiate("NativeBlockPrefab");asset.compose_frontage([load("res://addons/structures/prefabs/brick_cottage.tres")],8,8,3,1703)
	var survey=preload("res://addons/structures/site_survey.gd").new()
	var revision: int=terrain.density_revision
	var result: Dictionary=await survey.assess(terrain,asset,Vector3i(830,0,1310),0)
	var passed: bool=result.get("samples",0)==1584 and terrain.density_revision==revision and not terrain.pending_edit and not survey.busy
	if result.ok: passed=passed and result.grade>=result.minimum_grade and result.grade<=result.maximum_grade
	else: passed=passed and result.get("minimum_grade",0)>result.get("maximum_grade",0)
	print("SITE_SURVEY ",{"passed":passed,"result":result,"unchanged_density_revision":terrain.density_revision==revision})
	terrain.shutdown();terrain.free();quit(0 if passed else 1)
