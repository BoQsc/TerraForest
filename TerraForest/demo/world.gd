extends "res://demo/controller.gd"
const Vegetation = preload("res://addons/vegetation/vegetation_world.gd")
const Ecosystem = preload("res://addons/world_ecosystem/world_ecosystem.gd")
const Lakes = preload("res://addons/volumetric_water/lake_world.gd")
const Persistence = preload("res://addons/world_runtime/world_persistence.gd")
const Structures = preload("res://addons/structures/structures_world.gd")
var persistence = Persistence.new()
var generated_region=preload("res://addons/world_runtime/generated_region.gd").new()
var actor_authoring=preload("res://addons/world_runtime/actor_authoring.gd").new()
var zombies=preload("res://addons/characters/runtime/zombie_world.gd").new()
var zombie_target=preload("res://addons/characters/runtime/zombie_target.gd").new()
var navigation_residency=preload("res://addons/world_runtime/navigation_residency.gd").new()
var actors=preload("res://addons/world_runtime/actor_world.gd").new()
var model_paging: Node
# Native regional residency is the normal world path; retain an explicit diagnostic fallback.
var model_region_paging := not "--no-model-region-paging" in OS.get_cmdline_user_args()
var pickups = preload("res://addons/world_runtime/material_pickups.gd").new()
var player_pose: RefCounted
var world_vehicle=preload("res://addons/vehicle_runtime/world_vehicle.gd").new()
var _vehicle_ui_active:=false
var _walking_help:=""
var _saved_pose:=PackedByteArray()
var _restored_pose: Dictionary={}
var vegetation = Vegetation.new()
var ecosystem = Ecosystem.new()
var ground_cover=preload("res://addons/world_ecosystem/ground_cover.gd").new()
var ground_interaction=preload("res://addons/world_ecosystem/ground_interaction.gd").new()
var ground_enabled: bool="--ground-cover" in OS.get_cmdline_user_args()
var ground_preview=preload("res://addons/world_ecosystem/ground_preview.gd").new()
var ground_mode:=false
var ground_species:=0
var lakes = Lakes.new()
var water_camera=preload("res://addons/volumetric_water/water_camera.gd").new()
var structures = Structures.new()
var player_hud=preload("res://addons/player_runtime/player_hud.gd").new()
var world_map=preload("res://addons/world_runtime/world_map.gd").new()
var session_menu=preload("res://addons/player_runtime/session_menu.gd").new()
var destination_guide=preload("res://addons/player_runtime/destination_guide.gd").new()
var storage=preload("res://addons/player_runtime/storage.gd").new()
var doors=preload("res://addons/structures/door_interaction.gd").new()
var world_interaction=preload("res://demo/world_interaction.gd").new()
var construction_inventory=preload("res://addons/player_runtime/construction_inventory.gd").new()
var world_attack=preload("res://addons/player_runtime/world_attack.gd").new()
var equipped_tool:=0
var editor_tool_active:=false
var tool_view=preload("res://addons/player_runtime/tool_view.gd").new()
var tool_use_after:=0
var headlamp=preload("res://addons/player_runtime/headlamp.gd").new()
var mining_rewards=preload("res://addons/player_runtime/mining_rewards.gd").new()
var model_tool = preload("res://addons/structures/model_tool.gd").new()
var structure_mode := false
var construction_palette=preload("res://addons/structures/construction_palette.gd").new()
var road_palette=preload("res://addons/volumetric_terrain/road_palette.gd").new()
var road_authoring=preload("res://addons/volumetric_terrain/road_authoring.gd").new()
var road_preview=preload("res://addons/volumetric_terrain/road_preview.gd").new()
var structure_shape := 1
var structure_material := 0
var structure_rotation := 0
var structure_prefabs: Array[Resource] = []
var prefab_library=preload("res://addons/structures/prefab_library.gd").new()
var capture_selection=preload("res://addons/structures/capture_selection.gd").new()
var structure_prefab_index := -1
var prefab_preview := MeshInstance3D.new()
var shape_preview := MeshInstance3D.new()
var _shape_preview_material := StandardMaterial3D.new()
var _prefab_preview_material := StandardMaterial3D.new()
var _prefab_preview_timer := 0.0
var _prefab_preview_signature: Array = []
var _prefab_preview_clear := false
var _prefab_preview_needs_checks := false
var _prefab_preview_asset: Resource
var recent_action_messages: Array[String]=[]
var log_action_messages: bool="--log-actions" in OS.get_cmdline_user_args()
var telemetry := Label.new()
var _telemetry_time: float = 0.0
var _lake_notice: String = ""
var _lake_notice_until: int = 0
var foundation_check=preload("res://addons/structures/foundation_check.gd").new()
var _foundation_placement: Dictionary={}
var site_survey=preload("res://addons/structures/site_survey.gd").new()
var _survey_generation:=0
var site_preparation=preload("res://addons/structures/site_preparation.gd").new()
var _survey_plan: Dictionary={}
var site_preview=preload("res://addons/structures/site_preview.gd").new()

func _additional_motion_ready(delta: float) -> bool:
	if structures.blocks == null:
		return false
	# Cover capsule, floor snapping and any slide direction within this tick's
	# travel distance. The occupancy/readiness query itself is native.
	var bounds := AABB(player.global_position+Vector3(-0.34,-player.floor_snap_length,-0.34),Vector3(0.68,1.8+player.floor_snap_length,0.68))
	bounds.size.y+=0.3 # Native walking step-up head clearance.
	bounds = bounds.grow(player.velocity.length()*delta+0.05)
	return structures.is_collision_region_ready(bounds) and vegetation.is_collision_region_ready(bounds)

func _player_water_depth() -> float:
	return lakes.depth_at(player.global_position+Vector3(0,1.1,0))

var _initial_generation_spawn:=Vector3(800,0,1310)
func configure_generation_spawn(point:Vector3)->bool:
	if is_inside_tree() or not point.is_finite() or point.x<0 or point.x>2000 or point.z<0 or point.z>2000:return false
	_initial_generation_spawn=point
	return true

func _ready() -> void:
	construction_inventory.gameplay="--gameplay-construction" in OS.get_cmdline_user_args()
	player_hud.gameplay_construction=construction_inventory.gameplay
	tree_exiting.connect(prefab_library.shutdown_frontage)
	tree_exiting.connect(construction_inventory.cancel_prefab)
	add_child(world_vehicle)
	world_vehicle.interaction_available=_vehicle_interaction_available
	add_child(pickups)
	add_child(actors)
	if not actors.prepare(persistence):
		push_error("Actor persistence initialization failed");get_tree().quit(2);return
	if "--actors" in OS.get_cmdline_user_args() and not actors.enable():
		push_error("Actor activation initialization failed");get_tree().quit(2);return
	if not ground_cover.prepare(persistence):
		push_error("Ground-cover persistence initialization failed");get_tree().quit(2);return
	if not ecosystem.prepare_persistence(persistence):
		push_error("Vegetation persistence initialization failed")
		get_tree().quit(2)
		return
	if not pickups.prepare(persistence):
		push_error("Material pickup initialization failed")
		get_tree().quit(2)
		return
	structures.name = "Structures"
	add_child(structures)
	var beam := BoxMesh.new()
	var beam_material := StandardMaterial3D.new()
	beam_material.albedo_color = Color("3b5359")
	beam.material = beam_material
	var structures_ready: bool = structures.prepare() and structures.register_model("architecture/metal_beam/v1",beam) != null
	var doorway: Mesh = load("res://addons/structures/prefabs/doorway_model.tres")
	var door_models: Node3D = structures.register_model("architecture/doorway/v1",doorway)
	structures_ready = structures_ready and door_models != null
	structures_ready = structures_ready and preload("res://addons/structures/paving_catalog.gd").register(structures)
	var furniture: Array[Dictionary]=preload("res://addons/structures/furniture_catalog.gd").register(structures)
	structures_ready = structures_ready and furniture.size()==3
	var ladder: Dictionary=preload("res://addons/structures/ladder_catalog.gd").register(structures)
	structures_ready = structures_ready and not ladder.is_empty()
	var chest: Dictionary=preload("res://addons/structures/storage_catalog.gd").register(structures)
	structures_ready = structures_ready and not chest.is_empty()
	var window: Dictionary=preload("res://addons/structures/window_catalog.gd").register(structures)
	structures_ready = structures_ready and not window.is_empty()
	var door: Dictionary=preload("res://addons/structures/door_catalog.gd").register(structures)
	structures_ready = structures_ready and not door.is_empty() and doors.prepare(self)
	var guardrail: Dictionary=preload("res://addons/structures/guardrail_catalog.gd").register(structures)
	structures_ready = structures_ready and not guardrail.is_empty()
	var fence: Dictionary=preload("res://addons/structures/fence_catalog.gd").register(structures)
	structures_ready = structures_ready and not fence.is_empty()
	player_hud.ground_tools_enabled=ground_enabled
	if not generated_region.prepare(persistence):
		push_error("Generated region persistence initialization failed");get_tree().quit(2);return
	if not player_hud.prepare() or not persistence.register_component("player_loadout", player_hud.capture_snapshot, player_hud.restore_snapshot, player_hud.inventory, player_hud.default_loadout):
		push_error("Player loadout persistence initialization failed")
		get_tree().quit(2)
		return
	if not world_attack.prepare(self):
		push_error("World durability initialization failed");get_tree().quit(2);return
	if not persistence.register_component("player_equipment",player_hud.equipment.capture_storage_snapshot,player_hud.equipment.restore_storage_snapshot,player_hud.equipment,player_hud.equipment.capture_storage_snapshot()):
		push_error("Character equipment persistence initialization failed");get_tree().quit(2);return
	if not persistence.register_component("pending_rewards",player_hud.reward_inbox.capture_storage_snapshot,player_hud.reward_inbox.restore_storage_snapshot,player_hud.reward_inbox,player_hud.reward_inbox.capture_storage_snapshot()):
		push_error("Pending reward persistence initialization failed")
		get_tree().quit(2)
		return
	mining_rewards.enabled=construction_inventory.gameplay
	if not mining_rewards.attach(terrain,player_hud):
		push_error("Mining reward initialization failed")
		get_tree().quit(2)
		return
	player_pose=ClassDB.instantiate("NativePlayerPose")
	if not persistence.register_component("player_pose",_capture_player_pose,_restore_player_pose,player_pose,PackedByteArray()):
		push_error("Player pose persistence initialization failed")
		get_tree().quit(2)
		return
	if not world_vehicle.prepare(self,persistence):
		push_error("Vehicle persistence initialization failed")
		get_tree().quit(2)
		return
	if not road_palette.prepare_persistence(terrain,persistence):
		push_error("Road anchor persistence initialization failed")
		get_tree().quit(2)
		return
	var persistence_steps:Array=[
		["chest storage",func():return storage.prepare(self,persistence)],
		["structure catalog",func():return structures_ready],
		["water",func():return lakes.prepare()],
		["structure registration",func():return persistence.register_component("structures",structures.capture_storage_snapshot,storage.restore_structures,structures.snapshot_validator(),structures.empty_snapshot())],
		["water registration",func():return persistence.register_component("volumetric_water",lakes.capture_storage_snapshot,lakes.restore_snapshot,lakes.snapshot_validator(),lakes.empty_snapshot())],
		["regional archive",func():return persistence.enable_region_structures(true,model_region_paging)],
		["terrain attachment",func():return persistence.attach(terrain)==OK]]
	for step:Array in persistence_steps:
		if not step[1].call():
			push_error("World persistence initialization failed: "+step[0]);get_tree().quit(2);return
	_setup_prefabs()
	terrain.density_batch_ready.connect(foundation_check.receive)
	structures.blocks.configure_history(16*1024*1024,128)
	structures.blocks.configure_streaming(true,384,256,64*1024*1024,32*1024*1024)
	structures.model("architecture/metal_beam/v1").configure_collision(beam.get_aabb(),64,512,8)
	door_models.configure_compound_collision(doorway.get_meta("collision_boxes"),64,512,8,1536,24)
	terrain.nearby_first = true
	pending_spawn = _initial_generation_spawn
	terrain.focus = pending_spawn
	super._ready()
	movement.configure_ladders(ladder.collection)
	camera.add_child(headlamp)
	camera.add_child(tool_view)
	tool_view.human.body=player
	player.add_child(zombie_target)
	zombie_target.attacked.connect(func(damage:float):_show_lake_notice("Zombie hit · %.0f damage"%damage))
	add_child(zombies)
	zombies.enabled=(construction_inventory.gameplay or "--zombies" in OS.get_cmdline_user_args()) and not "--no-zombies" in OS.get_cmdline_user_args()
	if zombies.enabled:player.collision_mask |= zombies.CHARACTER_LAYER
	zombies.target=zombie_target
	zombies.readiness=_actor_collision_ready
	zombies.water_depth=lakes.water.depth_at
	zombies.obstacle_provider=_zombie_obstacle_target
	navigation_residency.game=self
	zombies.navigation_interest=navigation_residency.update
	add_child(model_tool)
	model_tool.gameplay=construction_inventory.gameplay
	model_tool.paid_placement=_place_inventory_model
	model_tool.gameplay_removal=_remove_inventory_model
	model_tool.availability=_model_edit_available
	var object_entries: Array[Dictionary]=[
		{"title":"Metal beam","mesh":beam,"collection":structures.model("architecture/metal_beam/v1"),"scale":Vector3(4,0.2,0.2),"costs":PackedInt64Array([104,4]),"cost_label":"4 metal"},
		{"title":"Floor panel","mesh":beam,"collection":structures.model("architecture/metal_beam/v1"),"scale":Vector3(4,0.25,4),"costs":PackedInt64Array([104,8]),"cost_label":"8 metal"},
		{"title":"Doorway","mesh":doorway,"collection":door_models,"scale":Vector3.ONE,"costs":PackedInt64Array([103,8]),"cost_label":"8 concrete"}]
	object_entries.append_array(furniture)
	object_entries.append(ladder)
	object_entries.append(chest)
	object_entries.append(window)
	object_entries.append(door)
	object_entries.append(guardrail)
	object_entries.append(fence)
	model_tool.configure(camera,player,object_entries,help.get_parent(),structures.blocks,structures._models.values())
	model_tool.notice.connect(_show_lake_notice)
	if model_region_paging and (not temporary_world or terrain.backend.readonly_snapshot):
		model_paging=preload("res://addons/structures/model_paging_coordinator.gd").new()
		add_child(model_paging)
		if not model_paging.attach(terrain,structures,model_tool.history,func():return player.global_position):
			push_error("Model paging lifecycle initialization failed")
			get_tree().quit(2)
			return
	player_hud.temporary_world=temporary_world
	add_child(player_hud)
	add_child(storage)
	session_menu.world_page_factory=_make_world_locations
	session_menu.game=self;session_menu.world_browser_path="res://demo/worlds.tscn";add_child(session_menu)
	session_menu.world_map=world_map;world_map.game=self;add_child(world_map)
	destination_guide.game=self;add_child(destination_guide)
	construction_palette.history_requested.connect(_construction_history)
	add_child(construction_palette)
	add_child(road_palette)
	road_palette.action_requested.connect(_road_action)
	terrain.add_child(road_preview)
	road_authoring.world=self;add_child(road_authoring)
	terrain.surface_batch_ready.connect(road_authoring.receive)
	terrain.add_child(site_preview)
	road_palette.selection_changed.connect(_update_road_preview)
	construction_palette.configure(structure_prefabs)
	construction_palette.selection_requested.connect(_construction_selection)
	construction_palette.capture_requested.connect(_capture_construction)
	construction_palette.supply_requested.connect(_place_material_supply)
	construction_palette.stack_requested.connect(_stack_construction)
	construction_palette.frontage_requested.connect(_frontage_construction)
	construction_palette.frontage_sources_requested.connect(_frontage_sources_construction)
	construction_palette.settlement_requested.connect(_frontage_sources_construction)
	construction_palette.survey_requested.connect(_survey_construction)
	construction_palette.preparation_requested.connect(_prepare_construction_site)
	construction_palette.prepared_placement_requested.connect(_place_prepared_site)
	construction_palette.preparation_status_requested.connect(_reopen_site_preparation)
	construction_palette.preparation_stop_requested.connect(site_preparation.cancel)
	construction_palette.survey_dialog.canceled.connect(_cancel_site_actions)
	construction_palette.survey_dialog.confirmed.connect(_cancel_site_actions)
	for dialog: Window in [construction_palette.survey_dialog,construction_palette.frontage_dialog]:
		dialog.focus_entered.connect(func(): _refresh_frame_cap.call_deferred())
		dialog.focus_exited.connect(func(): _refresh_frame_cap.call_deferred())
	player_hud.tool_requested.connect(_equip_player_tool)
	player_hud.menu_changed.connect(func(_open: bool): _clear_motion())
	player_hud.inventory_changed.connect(func(): terrain.changed_since_save=true)
	player_hud.drop_requested.connect(_drop_inventory_supply)
	pickups.changed.connect(func(): terrain.changed_since_save=true)
	structures.changed.connect(func():
		terrain.changed_since_save=true
		if actors.pool!=null:actors.pool.invalidate_navigation()
		zombies.invalidate_navigation())
	terrain.region_changed.connect(func(bounds: AABB,_revision: int):
		if actors.pool!=null:actors.pool.invalidate_navigation(bounds)
		zombies.invalidate_navigation(bounds))
	lakes.exclusion_changed.connect(func(bounds: AABB):
		if actors.pool!=null:actors.pool.invalidate_navigation(bounds)
		zombies.invalidate_navigation(bounds))
	world_vehicle.fleet.obstacles_changed.connect(func(bounds: AABB):
		if actors.pool!=null:actors.pool.invalidate_navigation(bounds)
		zombies.invalidate_navigation(bounds))
	actors.set_navigation_admission(func(point: Vector3):return lakes.depth_at(point-Vector3.UP*0.8)<=0)
	ecosystem.harvested.connect(func():
		terrain.changed_since_save=true
		if actors.pool!=null:actors.pool.invalidate_navigation()
		zombies.invalidate_navigation())
	_sync_player_tool()
	DisplayServer.window_set_title("TerraForest | Living terrain")
	vegetation.name = "Vegetation"
	vegetation.camera = camera
	vegetation.sun_direction = sun.global_basis.z.normalized()
	add_child(vegetation)
	if vegetation.initialize() != OK:
		_message("Vegetation initialization failed; inspect the log")
		return
	if not vegetation.enable_trunk_collision():
		push_error("Tree collision initialization failed");get_tree().quit(2);return
	if not "--no-tree-shadow-substitutes" in OS.get_cmdline_user_args():
		var canopy=preload("res://addons/vegetation/canopy_shadows.gd").new()
		canopy.name="CanopyShadows";canopy.forest=vegetation;canopy.camera=camera;canopy.material=terrain_material;add_child(canopy)
	ecosystem.name = "Ecosystem"
	ecosystem.terrain = terrain
	ecosystem.vegetation = vegetation
	ecosystem.camera = camera
	ecosystem.structures = structures
	ecosystem.water = lakes
	ecosystem.road_regions=generated_region.store
	ground_cover.road_regions=generated_region.store
	add_child(ecosystem)
	ground_cover.terrain=terrain;ground_cover.camera=camera;ground_cover.structures=structures;ground_cover.water=lakes
	ground_cover.seed_source=func():return terrain.backend.world_seed
	ground_cover.shelter_source=ecosystem.ground_shelter
	add_child(ground_cover);ground_cover.set_process(ground_enabled)
	add_child(ground_preview)
	ground_interaction.cover=ground_cover
	ground_interaction.scene_ray=func(from: Vector3,to: Vector3):return structures.blocks.raycast_scene(from,to,7,[player.get_rid()])
	ground_interaction.changed.connect(func():terrain.changed_since_save=true;player_hud.refresh())
	lakes.interaction_finished.connect(_show_lake_notice)
	lakes.bucket_completed.connect(func(slot:int):
		if player_hud.active_slot==slot:player_hud.equip_inventory(slot);tool_view.swing()
		else:player_hud.refresh())
	lakes.name = "Lakes"
	lakes.terrain = terrain
	lakes.blocks = structures.blocks
	add_child(lakes)
	add_child(water_camera)
	water_camera.configure(camera,lakes)
	if "--water-gameplay" in OS.get_cmdline_user_args():
		var start_water=preload("res://addons/volumetric_water/water_start.gd").new();start_water.game=self;add_child(start_water)
	lakes.lake_ready.connect(func(_id: int): _show_lake_notice("Lake ready · temporary world" if temporary_world else "Lake ready · F5 saves world"))
	lakes.lake_failed.connect(func(_id: int, code: int): _show_lake_notice("Lake rejected (%d): open basin or blocked seed" % code))

func _show_lake_notice(text: String) -> void:
	var sync_started:=Time.get_ticks_usec()
	_sync_construction_palette()
	terrain._record_stage("notice panel sync",(Time.get_ticks_usec()-sync_started)/1000.0)
	_lake_notice = text
	_lake_notice_until = Time.get_ticks_msec()+6000
	_telemetry_time = 0.5 # Publish action feedback on the next frame.
	var message_started:=Time.get_ticks_usec()
	recent_action_messages.append(text)
	if recent_action_messages.size()>64:recent_action_messages.pop_front()
	_present_message(text,log_action_messages or text.begins_with("ERROR:"))
	terrain._record_stage("notice message",(Time.get_ticks_usec()-message_started)/1000.0)

func _capture_player_pose() -> PackedByteArray:
	# Resource placement is transient; the v1 pose stores only original tool IDs.
	var saved_tool: int=player_hud.active_item if player_hud.active_item in player_hud.CATALOG else 0
	if world_vehicle.driving:
		var feet:=world_vehicle.safe_exit_position(self)
		var captured: PackedByteArray=player_pose.encode(feet,wrapf(yaw,-PI,PI),pitch,false,saved_tool) if feet.is_finite() else PackedByteArray()
		# Reject the compound save if no safe on-foot restore point exists.
		return captured if not captured.is_empty() else PackedByteArray([0])
	if not loading_active and not waiting_spawn and not world_vehicle.driving:
		var captured: PackedByteArray=player_pose.encode(player.position,wrapf(yaw,-PI,PI),pitch,fly,saved_tool)
		if not captured.is_empty(): _saved_pose=captured
	return _saved_pose

func _restore_player_pose(data: PackedByteArray) -> bool:
	var decoded: Dictionary=player_pose.decode(data)
	if not decoded.ok: return false
	zombies.clear()
	zombie_target.damage_received=0.0
	ground_mode=false;equipped_tool=0;editor_tool_active=false
	player_hud.show_ground_tool(-1)
	_saved_pose=data
	_restored_pose=decoded
	return true

func _terrain_initialized(text: String) -> void:
	if _restored_pose.has("position"):
		pending_spawn=_restored_pose.position
		spawn_override_y=pending_spawn.y
		fly=_restored_pose.fly and session_menu.developer
		yaw=_restored_pose.yaw
		pitch=_restored_pose.pitch
		player.rotation.y=yaw
		camera.rotation.x=pitch
		# Put saved modes away during loading; choose a default gameplay tool only when ready.
		equipped_tool=0;editor_tool_active=false;structure_mode=false;model_tool.set_active(false);tool_view.equip(0)
		player_hud.active_slot=-1;player_hud.show_active_tool(0)
	else:
		pending_spawn=_initial_generation_spawn
		spawn_override_y=-1.0
	_restored_pose.clear()
	super._terrain_initialized(text)

func _setup_prefabs() -> void:
	add_child(capture_selection)
	prefab_library.load_library()
	for path in ["res://addons/structures/prefabs/brick_cottage.tres","res://addons/structures/prefabs/stair_flight.tres","res://addons/structures/prefabs/doorway_wall.tres","res://addons/structures/prefabs/tower_floor.tres"]:
		var asset: Resource = load(path)
		if asset != null and asset.get_cell_count()>0:
			structure_prefabs.append(asset)
			asset.changed.connect(_invalidate_prefab_preview)
	var furnished: Resource=preload("res://addons/structures/furniture_catalog.gd").furnished_cottage(true)
	if furnished!=null:
		structure_prefabs.append(furnished);furnished.changed.connect(_invalidate_prefab_preview)
	var frontage=ClassDB.instantiate("NativeBlockPrefab")
	var cottage: Resource=load("res://addons/structures/prefabs/brick_cottage.tres")
	if frontage.compose_frontage([cottage],2,8,3,1703):
		frontage.resource_name="Street frontage · 4 cottages (ungraded)"
		frontage.set_meta("frontage_version",1)
		frontage.set_meta("street_width",8);frontage.set_meta("frontage_gap",3)
		structure_prefabs.append(frontage)
		frontage.changed.connect(_invalidate_prefab_preview)
	structures.blocks.changed.connect(_invalidate_prefab_preview)
	var enclosed: Resource=preload("res://addons/structures/furniture_catalog.gd").enclosed_cottage()
	if enclosed!=null:
		structure_prefabs.append(enclosed);enclosed.changed.connect(_invalidate_prefab_preview)
	var tower: Resource=preload("res://addons/structures/furniture_catalog.gd").furnished_tower()
	if tower!=null:
		structure_prefabs.append(tower);tower.changed.connect(_invalidate_prefab_preview)
	var bridge: Resource=preload("res://addons/structures/bridge_catalog.gd").footbridge()
	var workshop: Resource=preload("res://addons/structures/workshop_catalog.gd").workshop()
	if workshop!=null:
		structure_prefabs.append(workshop);workshop.changed.connect(_invalidate_prefab_preview)
	if bridge!=null:
		structure_prefabs.append(bridge);bridge.changed.connect(_invalidate_prefab_preview)
	var metal_bridge: Resource=preload("res://addons/structures/bridge_catalog.gd").footbridge(true)
	if metal_bridge!=null:
		structure_prefabs.append(metal_bridge);metal_bridge.changed.connect(_invalidate_prefab_preview)
	for asset: Resource in prefab_library.assets:
		structure_prefabs.append(asset)
		asset.changed.connect(_invalidate_prefab_preview)
	# A single bounds outline is UI feedback, not another building simulation.
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0,0,0),Vector3(1,0,0),Vector3(1,0,1),Vector3(0,0,1),Vector3(0,1,0),Vector3(1,1,0),Vector3(1,1,1),Vector3(0,1,1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,1,2,2,3,3,0,4,5,5,6,6,7,7,4,0,4,1,5,2,6,3,7])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,arrays)
	prefab_preview.mesh = mesh
	_prefab_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	prefab_preview.material_override = _prefab_preview_material
	prefab_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	prefab_preview.hide()
	add_child(prefab_preview)
	_shape_preview_material.shading_mode=StandardMaterial3D.SHADING_MODE_UNSHADED
	_shape_preview_material.transparency=StandardMaterial3D.TRANSPARENCY_ALPHA
	shape_preview.material_override=_shape_preview_material
	shape_preview.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shape_preview.hide()
	add_child(shape_preview)

func _prefab_allowed(asset: Resource, target: Vector3i) -> bool:
	var bounds: AABB = asset.placement_bounds(target,structure_rotation)
	return _prefab_player_clear(bounds) and structures.blocks.can_place_prefab(asset,target,structure_rotation)

func _prefab_player_clear(bounds: AABB) -> bool:
	var player_bounds := AABB(player.global_position+Vector3(-0.4,0,-0.4),Vector3(0.8,1.8,0.8))
	return not bounds.intersects(player_bounds)

func _invalidate_prefab_preview() -> void:
	_survey_generation+=1
	_prefab_preview_asset=null
	_prefab_preview_signature.clear()
	if not _foundation_placement.is_empty(): foundation_check.status="Layout changed; place again"
	_prefab_preview_timer=0.0

func _update_prefab_preview(delta: float) -> void:
	if world_vehicle.driving:
		prefab_preview.hide();shape_preview.hide();capture_selection.hide();return
	capture_selection.visible=structure_mode and not model_tool.active and not loading_active and not player_hud.inventory_open
	if not structure_mode or model_tool.active or loading_active or not app_focused or player_hud.inventory_open or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:
		prefab_preview.hide()
		shape_preview.hide()
		return
	_prefab_preview_timer -= delta
	if _prefab_preview_timer>0:
		return
	_prefab_preview_timer=0.1
	var hit := _structure_target(false)
	if hit.is_empty():
		prefab_preview.hide()
		shape_preview.hide()
		return
	if structure_prefab_index<0:
		prefab_preview.position=Vector3(hit.target)
		prefab_preview.scale=Vector3.ONE
		_prefab_preview_material.albedo_color=Color("66f2b3") if _block_player_clear(hit.target) else Color("ff705f")
		shape_preview.mesh=structures.blocks.preview_mesh(structure_shape,structure_rotation)
		shape_preview.position=Vector3(hit.target)
		var tint: Color=_prefab_preview_material.albedo_color
		tint.a=0.35
		_shape_preview_material.albedo_color=tint
		shape_preview.show()
		prefab_preview.show()
		return
	shape_preview.hide()
	var asset: Resource = structure_prefabs[structure_prefab_index]
	if asset.get_cell_count()==0:
		prefab_preview.hide()
		return
	var bounds: AABB = asset.placement_bounds(hit.target,structure_rotation)
	var signature: Array = [structure_prefab_index,hit.target,structure_rotation]
	if _prefab_preview_asset!=asset:
		_prefab_preview_asset=asset
		_prefab_preview_needs_checks=asset.has_meta("frontage_version") or not asset.get_model_attachments().is_empty()
	if signature != _prefab_preview_signature:
		# Pending placement checks are amber. Do not scan an entire furnished
		# building every time the aim moves; its native transaction checks cells.
		_prefab_preview_clear=_prefab_preview_needs_checks or structures.blocks.can_place_prefab(asset,hit.target,structure_rotation)
		_prefab_preview_signature=signature
	prefab_preview.position=bounds.position
	prefab_preview.scale=bounds.size
	var clear: bool=_prefab_preview_clear and _prefab_player_clear(bounds) and not world_vehicle.overlaps_edit(bounds)
	_prefab_preview_material.albedo_color=Color("ff705f")
	if clear:
		_prefab_preview_material.albedo_color=Color("edc66a") if _prefab_preview_needs_checks else Color("66f2b3")
	prefab_preview.show()

func _message(text: String) -> void:
	_present_message(text,true)

func _present_message(text: String,console_output: bool) -> void:
	var label_started:=Time.get_ticks_usec()
	status.text=text
	var label_us:=Time.get_ticks_usec()-label_started
	var log_started:=Time.get_ticks_usec()
	if console_output and (text.begins_with("ERROR:") or "--verbose-world-events" in OS.get_cmdline_user_args()):print("[TerrainRewrite] ",text)
	var log_us:=Time.get_ticks_usec()-log_started
	if terrain!=null:
		terrain._record_stage("message label",label_us/1000.0)
		terrain._record_stage("message console",log_us/1000.0)
	if text.begins_with("World saved") or text.begins_with("World loaded") or text.begins_with("Temporary") or text.begins_with("ERROR:"):
		_lake_notice = "World saved" if text.begins_with("World saved") else "World loaded"
		if text.begins_with("Temporary"):
			_lake_notice = "Temporary world · changes are not saved"
		if text.begins_with("ERROR:"):
			_lake_notice = "World operation failed · F3 for details"
		_lake_notice_until = Time.get_ticks_msec()+6000

func create_lake(point: Vector3) -> int:
	# Explicit authoring action: carve first, bake after terrain publication.
	# The next compound world snapshot includes this lake definition and terrain.
	if terrain.pending_edit or not terrain.world_ready:
		return 0
	var center: Vector3 = point.floor()
	var id: int = lakes.add_lake(center - Vector3(20,8,12), Vector3i(40,12,24), 1.0, center.y-0.75, center-Vector3(0,2,0))
	if id == 0:
		return 0
	var a:=center+Vector3(-6,1.5,0)
	var b:=center+Vector3(6,1.5,0)
	if not terrain.edit(Codec.brush(a,b,6.0,0,false,1),a,b):
		lakes.remove_lake(id)
		return 0
	return id

func _setup_scene() -> void:
	super._setup_scene()
	player.collision_mask |= 6
	player.position = Vector3(800, 100, 1310)
	for child in get_children():
		if child is WorldEnvironment:
			var environment: Environment = child.environment
			var sky := Sky.new()
			# Reuse the static sky for material reflections. A small radiance map
			# is filtered once; this does not render the world again or use SSR.
			sky.radiance_size = Sky.RADIANCE_SIZE_128
			var sky_material := ProceduralSkyMaterial.new()
			sky_material.sky_top_color = Color("527b9a")
			sky_material.sky_horizon_color = Color("c4d6d8")
			sky_material.ground_bottom_color = Color("303d37")
			sky_material.ground_horizon_color = Color("c4d6d8")
			sky.sky_material = sky_material
			environment.sky = sky
			environment.background_mode = Environment.BG_SKY
			environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
			environment.ambient_light_energy = 0.35
			environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
			environment.fog_enabled = true
			environment.fog_light_color = Color("a7c4cd")
			environment.fog_density = 0.00055
			environment.fog_sky_affect = 0.2

func _setup_hud() -> void:
	super._setup_hud()
	hud.hide()
	status.hide()
	help.text = "WASD  Move    Shift  Sprint    Space  Jump    G  Fly    Mouse  Look    Esc  Release\nB  Terrain / Blocks    LMB  Remove    RMB  Place    1–6  Shapes    P  Prefabs    T  Material    R  Rotate    Ctrl+Z / Y  Undo / Redo\nTerrain: Wheel  Brush size    1–3  Tools    L  Lake    F5  Save world    F9  Reload    F3  Diagnostics"
	help.add_theme_font_size_override("font_size", 15)
	help.text=help.text.replace("B  Terrain / Blocks", "B  Terrain / Blocks    M  Objects    E  Collect / Harvest / Open chest")
	help.text+="\nV  Place vehicle    E  Enter / exit stopped vehicle    F5  Save world and vehicle    F  Headlamp"
	if ground_enabled: help.text+="    H Ground cover: 1-8 select; LMB/E remove; RMB place; F7 Grass texture"
	help.offset_top = -108
	help.add_theme_color_override("font_color", Color("e6eee9"))
	var panel := PanelContainer.new()
	panel.position = Vector2(26, 24)
	panel.custom_minimum_size = Vector2(340, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.07, 0.065, 0.88)
	style.border_color = Color("70bca0")
	style.border_width_left = 3
	style.content_margin_left = 19
	style.content_margin_right = 22
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	panel.add_child(box)
	var eyebrow := Label.new()
	eyebrow.text = "T E R R A F O R E S T"
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", Color("83d6b2"))
	box.add_child(eyebrow)
	var title := Label.new()
	title.text = "Living terrain"
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	telemetry.add_theme_font_size_override("font_size", 14)
	telemetry.add_theme_color_override("font_color", Color("bbcfc6"))
	box.add_child(telemetry)
	help.get_parent().add_child(panel)
	hud.position = Vector2(26, 200)
	status.position = Vector2(26, 570)

func _cancel_edit_input()->void:
	world_attack.cancel()
	super._cancel_edit_input()

func _equip_player_tool(item: int) -> void:
	if world_vehicle.driving:return
	editor_tool_active=false;equipped_tool=item
	_set_player_tool_mode(item in [3,4] or item in player_hud.MATERIALS,item==4,3)
	if item in player_hud.MATERIALS:
		structure_shape=1;structure_prefab_index=-1;structure_material=item-101;_sync_construction_palette()
	if item in player_hud.GROUND_ITEMS:_activate_ground_tool(player_hud.GROUND_ITEMS[item])
	if item==1:radius=0.65
	edit_reach=3.5;allow_terrain_add=false
	tool_view.equip(item if item in player_hud.CATALOG or (item>=401 and item<=411) else 0)
	player_hud.show_active_tool(item)
	if session_menu.developer_hud!=null:session_menu.developer_hud.refresh()
	_show_lake_notice(session_menu.DESCRIPTIONS.get(item,"Empty hands - left mouse punches, E interacts" if item==0 else "Holding "+player_hud.MATERIALS.get(item,player_hud.RESOURCES.get(item,"item"))))

func _activate_ground_tool(species: int) -> bool:
	if not ground_enabled or world_vehicle.driving or species<0 or species>=player_hud.GroundCatalog.COUNT:return false
	if not _set_player_tool_mode(false,false,tool):return false
	ground_mode=true;ground_species=species
	player_hud.show_ground_tool(species)
	player_hud.show_active_tool(player_hud.GroundCatalog.ITEMS[species])
	_show_lake_notice(player_hud.GroundCatalog.NAMES[species]+"; LMB/E remove; RMB place")
	return true
func _sync_player_tool() -> void:
	player_hud.editor_hint=("DEVELOPMENT | "+("Object editor" if model_tool.active else ("Block editor" if structure_mode else "Terrain brush"))+" | Hold Alt: tool controls | Left mouse: remove | Right mouse: place / fill") if editor_tool_active else ""
	_sync_construction_palette()
	player_hud.show_active_tool(equipped_tool)

func _sync_construction_palette() -> void:
	construction_palette.synchronize(structure_mode and not model_tool.active,structure_shape,structure_material,structure_rotation,structure_prefab_index,not session_menu.ready_to_dock)
	if construction_palette.archive_button!=null:
		construction_palette.archive_button.disabled=structure_prefab_index<0 or not prefab_library.owns(structure_prefabs[structure_prefab_index])
	session_menu.sync_panels()

func _capture_construction(action: String,title: String) -> void:
	if loading_active or shutdown_requested or benchmark_enabled or player_hud.inventory_open or not structure_mode or model_tool.active: return
	if action=="archive":
		if structure_prefab_index<0: return
		var asset: Resource=structure_prefabs[structure_prefab_index]
		var result: Dictionary=prefab_library.archive(asset)
		if not result.ok:
			construction_palette.capture_status.text=result.reason
			return
		asset.changed.disconnect(_invalidate_prefab_preview)
		structure_prefabs.remove_at(structure_prefab_index);structure_prefab_index=-1
		construction_palette.configure(structure_prefabs)
		construction_palette.capture_status.text="Archived %s · placed blocks retained" % asset.resource_name
		_sync_construction_palette();_invalidate_prefab_preview()
		return
	if action=="restore":
		var result: Dictionary=prefab_library.restore_latest()
		if not result.ok:
			construction_palette.capture_status.text=result.reason
			return
		structure_prefabs.append(result.asset);result.asset.changed.connect(_invalidate_prefab_preview)
		structure_prefab_index=structure_prefabs.size()-1
		construction_palette.configure(structure_prefabs)
		construction_palette.capture_status.text="Restored "+result.asset.resource_name
		_sync_construction_palette();_invalidate_prefab_preview()
		return
	if action=="clear":
		prefab_library.clear_selection()
		capture_selection.synchronize(prefab_library)
		construction_palette.capture_status.text="Aim at a block, then mark each corner."
		return
	if action in ["a","b"]:
		var hit:=_structure_target(true)
		if hit.is_empty():
			construction_palette.capture_status.text="Aim at a building block to mark a corner."
			return
		prefab_library.select_corner(action=="a",hit.target)
		capture_selection.synchronize(prefab_library)
		construction_palette.capture_status.text=prefab_library.selection_text()
	elif action=="save":
		var result: Dictionary=prefab_library.capture(structures.blocks,title,structures.model_collections().values())
		if not result.ok:
			construction_palette.capture_status.text=result.reason
			return
		structure_prefabs.append(result.asset)
		result.asset.changed.connect(_invalidate_prefab_preview)
		structure_prefab_index=structure_prefabs.size()-1
		construction_palette.configure(structure_prefabs)
		construction_palette.capture_status.text="Saved %s · %d blocks" % [title,result.asset.get_cell_count()]
		_sync_construction_palette()
		_invalidate_prefab_preview()

func _stack_construction(count: int,title: String) -> void:
	if loading_active or shutdown_requested or benchmark_enabled or player_hud.inventory_open or not structure_mode or model_tool.active or structure_prefab_index<0: return
	var result: Dictionary=prefab_library.stack(structure_prefabs[structure_prefab_index],count,title)
	_accept_composed_prefab(result)

func _frontage_construction(lots: int,width: int,gap: int,seed: int,title: String) -> void:
	if loading_active or shutdown_requested or benchmark_enabled or player_hud.inventory_open or not structure_mode or model_tool.active or structure_prefab_index<0: return
	var result: Dictionary=prefab_library.begin_frontage(structure_prefabs[structure_prefab_index],lots,width,gap,seed,title)
	construction_palette.capture_status.text="Generating frontage…" if result.ok else result.reason

func _frontage_sources_construction(indices: PackedInt32Array,lots: int,width: int,gap: int,seed: int,title: String,streets: int=1) -> void:
	if loading_active or shutdown_requested or benchmark_enabled or player_hud.inventory_open or not structure_mode or model_tool.active: return
	var sources: Array[Resource]=[]
	for index in indices:
		if index<0 or index>=structure_prefabs.size(): construction_palette.capture_status.text="Building selection changed; reopen the street tool";return
		sources.append(structure_prefabs[index])
	var result: Dictionary=prefab_library.begin_frontage_sources(sources,lots,width,gap,seed,title,streets)
	construction_palette.capture_status.text=("Generating settlement…" if streets>1 else "Generating mixed frontage…") if result.ok else result.reason

func _accept_composed_prefab(result: Dictionary) -> void:
	if not result.ok:
		construction_palette.capture_status.text=result.reason
		return
	structure_prefabs.append(result.asset)
	result.asset.changed.connect(_invalidate_prefab_preview)
	structure_prefab_index=structure_prefabs.size()-1
	construction_palette.configure(structure_prefabs)
	construction_palette.capture_status.text="Saved %s · %d blocks" % [result.asset.resource_name,result.asset.get_cell_count()]
	_sync_construction_palette();_invalidate_prefab_preview()

func _construction_selection(field: String,value: int) -> void:
	if loading_active or shutdown_requested or benchmark_enabled or player_hud.inventory_open or not structure_mode or model_tool.active:
		_sync_construction_palette()
		return
	match field:
		"shape":
			if value<0 or value>=6: return
			structure_shape=value+1;structure_prefab_index=-1
		"material":
			if value<0 or value>=4: return
			structure_material=value
		"rotation":
			if value<0 or value>=4: return
			structure_rotation=value
		"prefab":
			if value<0 or value>structure_prefabs.size(): return
			structure_prefab_index=value-1
		_: return
	_prefab_preview_timer=0.0
	_sync_construction_palette()

func _set_player_tool_mode(building: bool,objects: bool,terrain_tool: int) -> bool:
	if loading_active or benchmark_enabled or shutdown_requested or not app_focused or not terrain.world_ready: return false
	# All tool entry points cancel unsubmitted strokes before changing mode.
	# Already accepted terrain edits finish independently; they do not lock equipment.
	_cancel_edit_input()
	stroke_buffer.clear();held_previous=false
	ground_mode=false
	player_hud.show_ground_tool(-1)
	model_tool.set_active(objects)
	structure_mode=building
	tool=terrain_tool
	_sync_player_tool()
	_show_lake_notice(player_hud.CATALOG.get(player_hud.active_item,"Terrain editing"))
	return true

func _movement_input_available() -> bool:
	return super._movement_input_available() or (session_menu!=null and session_menu.developer_hud!=null and session_menu.developer_hud.mouse_access and not session_menu.visible_ui() and not player_hud.inventory_open)

func _unhandled_input(event: InputEvent) -> void:
	if session_menu.visible_ui():return
	if player_hud.inventory_open: return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_K:
		_show_lake_notice(actor_authoring.command(self,event.shift_pressed));return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_J:
		_show_lake_notice(actor_authoring.apply(self,event.shift_pressed));return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F:
		if session_menu.tilde_down>=0:return
		if app_focused and not loading_active and not shutdown_requested and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
			_show_lake_notice("Headlamp on" if headlamp.toggle() else "Headlamp off")
		return
	if world_vehicle.driving:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode==KEY_F5 and app_focused and not loading_active and not shutdown_requested:
				if world_vehicle.safe_exit_position(self).is_finite(): terrain.save_world()
				else: _show_lake_notice("Cannot save here · move beside clear, loaded ground")
			elif event.physical_keycode==KEY_E:
				_show_lake_notice(world_vehicle.exit_vehicle(self));_clear_motion()
			elif event.physical_keycode==KEY_ESCAPE:
				Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if Input.mouse_mode==Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
		return
	if not session_menu.developer and equipped_tool>=401 and equipped_tool<=411 and event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT] and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		if event.pressed and _model_edit_available():
			var start:Vector3=camera.global_position
			var end:Vector3=start-camera.global_basis.z*3.5
			var hit:Dictionary=structures.blocks.raycast_scene(start,end,0xFFFFFFFF,[player.get_rid()])
			# Placement clearance is only for pours. Applying it to a scoop
			# cuts off visible water shallower than 1 cm before the ray reaches it.
			if not hit.is_empty():end=hit.position+hit.normal*(0.01 if event.button_index==MOUSE_BUTTON_RIGHT else 0.0)
			elif event.button_index==MOUSE_BUTTON_RIGHT and not lakes.water.raycast_surface(start,end).hit and not lakes.water.raycast_vacancy(start,end).hit:
				_show_lake_notice("Aim at nearby terrain or water to pour");return
			var result:Dictionary=lakes.bucket(start,end,event.button_index==MOUSE_BUTTON_RIGHT,player_hud.inventory,player_hud.active_slot,player_hud.inventory.snapshot().revision)
			if result.ok:player_hud.equip_inventory(player_hud.active_slot);tool_view.swing()
			_show_lake_notice(result.reason)
		return
	if not session_menu.developer and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		if event.pressed:world_attack.attack()
		return
	if ground_enabled and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_F7:
		if ground_cover.set_grass_texture(not ground_cover.grass_texture_enabled):
			_show_lake_notice("Grass texture: "+("subtle" if ground_cover.grass_texture_enabled else "off"))
		else:_show_lake_notice("Grass texture could not load")
		return
	if ground_enabled and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_H:
		if ground_mode:_set_player_tool_mode(false,false,tool)
		else:_activate_ground_tool(ground_species)
		return
	if ground_mode:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7,KEY_8]:
			ground_species=event.physical_keycode-KEY_1
			player_hud.show_ground_tool(ground_species)
			player_hud.show_active_tool(player_hud.GroundCatalog.ITEMS[ground_species])
			_show_lake_notice(player_hud.GroundCatalog.NAMES[ground_species]+"; LMB remove; RMB place");return
		var remove_action: bool=event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_E
		var mouse_action: bool=event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]
		if mouse_action:
			if _model_edit_available() and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and (remove_action or event.pressed):
				var origin:=camera.global_position
				var endpoint:=origin-camera.global_basis.z*(2.5 if construction_inventory.gameplay else 8.0)
				var result: Dictionary=ground_interaction.collect(origin,endpoint,player_hud.inventory,construction_inventory.gameplay) if remove_action or event.button_index==MOUSE_BUTTON_LEFT else ground_interaction.place(ground_species,origin,endpoint,player_hud.inventory,construction_inventory.gameplay)
				if result.ok and result.has("id"):world_attack.durability.forget("cover:%d"%result.id)
				_show_lake_notice(result.reason)
			return
	if event is InputEventKey and event.pressed and not event.echo and not loading_active and not shutdown_requested and app_focused and not fly and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		if event.physical_keycode==KEY_V:
			_show_lake_notice(world_vehicle.spawn(self));return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_E and not fly:
		if not loading_active and not shutdown_requested and app_focused and terrain.world_ready and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
			# Directly aimed interactions take priority over proximity-based entry.
			if world_interaction.interact(self): return
			if world_vehicle.enter(self):
				_clear_motion();_show_lake_notice("Driving · E exit when stopped · Space brake");return
			# Attacks exclusively use left mouse; E remains interaction.
			var collected: Dictionary=pickups.collect_near(player.global_position+Vector3(0,0.5,0),player_hud.inventory,_pickup_reachable)
			if collected.ok: player_hud.refresh()
			_show_lake_notice(collected.reason)
		return
	if not loading_active and not benchmark_enabled:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_B:
				_set_player_tool_mode(not structure_mode,false,tool)
				return
			if not structure_mode and event.physical_keycode in [KEY_1,KEY_2,KEY_3,KEY_4]:
				_set_player_tool_mode(false,false,event.physical_keycode-KEY_1+1)
				return
		if model_tool.active and app_focused and terrain.world_ready:
			if model_tool.handle_input(event):
				return
		if event is InputEventKey and event.pressed and not event.echo:
			if structure_mode and not model_tool.active:
				if event.physical_keycode in [KEY_BRACKETLEFT,KEY_BRACKETRIGHT]:
					_capture_construction("a" if event.physical_keycode==KEY_BRACKETLEFT else "b","")
					get_viewport().set_input_as_handled()
					return
				if (event.ctrl_pressed or event.meta_pressed) and event.physical_keycode in [KEY_Z,KEY_Y]:
					_construction_history(event.physical_keycode==KEY_Y or event.shift_pressed)
					return
				if event.physical_keycode == KEY_P:
					structure_prefab_index += 1
					if structure_prefab_index >= structure_prefabs.size():
						structure_prefab_index = -1
					_prefab_preview_timer=0.0
					_show_lake_notice("Single blocks" if structure_prefab_index<0 else "%s · R rotate · RMB place · green bounds required" % structure_prefabs[structure_prefab_index].resource_name)
					return
				var handled := true
				if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_6:
					structure_prefab_index = -1
					structure_shape = event.physical_keycode-KEY_1+1
				elif event.physical_keycode == KEY_T:
					structure_material = (structure_material+1)%4
				elif event.physical_keycode == KEY_R:
					structure_rotation = (structure_rotation+1)%4
				else:
					handled = false
				if handled:
					_prefab_preview_timer=0.0
					_show_lake_notice("%s · %d°" % [structure_prefabs[structure_prefab_index].resource_name,structure_rotation*90] if structure_prefab_index>=0 else "%s · %s · %d°" % [["Cube","Slab","Stairs","Slope","Post","Sphere","Round column"][structure_shape-1],["Brick","Wood","Concrete","Metal"][structure_material],structure_rotation*90])
					return
		if structure_mode and not model_tool.active and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT] and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_edit_structure(event.button_index == MOUSE_BUTTON_LEFT)
			return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_L:
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position-camera.global_basis.z*80.0, 1)
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			_show_lake_notice("Carving lake; waiting for terrain" if create_lake(hit["position"]) != 0 else "Lake creation unavailable")
		else:
			_show_lake_notice("Aim at nearby terrain to carve a lake")
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		hud.visible = not hud.visible
		status.visible = hud.visible
		return
	super._unhandled_input(event)

func _update_edit(delta: float) -> void:
	if not session_menu.developer:
		if input_vector!=Vector3.ZERO:terrain.note_interaction()
		pointer.hide();terrain.set_brush_active(false)
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):world_attack.attack()
		return
	if not editor_tool_active:
		pointer.hide();terrain.set_brush_active(false);return
	if session_menu.visible_ui():
		pointer.hide();terrain.set_brush_active(false);return
	edit_reach=120.0 if editor_tool_active else 3.5
	allow_terrain_add=editor_tool_active
	if ground_mode:
		pointer.hide();terrain.set_brush_active(false);return
	if world_vehicle.driving:
		pointer.hide();terrain.set_brush_active(false);return
	if player_hud.inventory_open:
		pointer.hide()
		terrain.set_brush_active(false)
		return
	if structure_mode:
		pointer.hide()
		if input_vector != Vector3.ZERO:
			terrain.note_interaction()
		terrain.set_brush_active(false)
		return
	super._update_edit(delta)
	if equipped_tool==1 and terrain.pending_edit and not editor_tool_active:tool_view.swing()

func _construction_history(forward: bool) -> void:
	if construction_inventory.gameplay:
		_show_lake_notice("Construction history is available in the free editor")
		return
	if not terrain.world_ready:
		return
	if (forward and not structures.blocks.can_redo()) or (not forward and not structures.blocks.can_undo()):
		_show_lake_notice("No construction to redo" if forward else "No construction to undo")
		return
	var protection := AABB(player.global_position+Vector3(-0.4,0,-0.4),Vector3(0.8,1.8,0.8))
	var applied: bool = structures.blocks.redo(protection) if forward else structures.blocks.undo(protection)
	_show_lake_notice(("Construction redone · F5 saves world" if forward else "Construction undone · F5 saves world") if applied else "History blocked · move clear of the blocks being restored")

func _structure_target(remove: bool) -> Dictionary:
	var origin := camera.global_position
	var hit: Dictionary = structures.blocks.raycast_scene(origin,origin-camera.global_basis.z*(4.0 if construction_inventory.gameplay else 48.0),3,[player.get_rid()])
	if hit.is_empty():
		return {}
	var building_hit: bool = hit.has("cell") and hit.collider==structures.blocks
	if remove and not building_hit:
		return {}
	var target := Vector3i((hit.position + hit.normal*0.001).floor())
	if building_hit:
		target = hit.cell
		if not remove:
			var normal: Vector3 = hit.cell_normal
			var axis := normal.abs().max_axis_index()
			target[axis] += 1 if normal[axis]>0 else -1
	return {"target":target,"position":hit.position,"normal":hit.normal}

func _place_material_supply(item: int) -> void:
	if construction_inventory.gameplay:
		_show_lake_notice("Supply spawning is available in the free editor")
		return
	if loading_active or shutdown_requested or benchmark_enabled or not app_focused or not terrain.world_ready or player_hud.inventory_open or not structure_mode or model_tool.active: return
	if item not in pickups.ITEMS: return
	var hit:=_structure_target(false)
	if hit.is_empty() or hit.normal.y<0.7:
		_show_lake_notice("Aim at a supporting surface for the supply")
		return
	var point: Vector3=hit.position+Vector3(0,0.2,0)
	var bounds:=AABB(point-Vector3.ONE*0.2,Vector3.ONE*0.4)
	if not structures.is_collision_region_ready(bounds):
		_show_lake_notice("Supply placement waiting for nearby collision")
		return
	var shape:=BoxShape3D.new();shape.size=Vector3.ONE*0.35
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,point);query.collision_mask=3
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
		_show_lake_notice("Supply placement is obstructed")
		return
	for store: RefCounted in pickups.stores.values():
		var nearby: Dictionary=store.query_sphere(pickups.to_local(point),0.5,1,64)
		if not nearby.ok or not nearby.complete or not nearby.ids.is_empty():
			_show_lake_notice("Supply placement overlaps another supply")
			return
	if pickups.spawn(item,pickups.to_local(point))==0:
		_show_lake_notice("Supply capacity reached")
		return
	_show_lake_notice("%s supply placed · %s" % [pickups.ITEMS[item],"temporary world" if temporary_world else "F5 saves world"])

func _update_road_preview() -> void:
	road_authoring.cancel("Road selection changed; prepare the smooth preview again.")
	if not road_palette.has_start and not road_palette.has_finish:
		road_preview.clear();return
	var a: Vector3=road_palette.start if road_palette.has_start else road_palette.finish
	var b: Vector3=road_palette.finish if road_palette.has_finish else a
	road_preview.update_selection(a,b,road_palette.width.value,road_palette.depth.value,road_palette.validation_error().is_empty(),road_palette.clearance.value,road_palette.shoulder_width())

func _road_action(action: String) -> void:
	if loading_active or shutdown_requested or benchmark_enabled or not app_focused or not terrain.world_ready or player_hud.inventory_open or structure_mode or model_tool.active: return
	if action=="smooth":road_authoring.prepare();return
	if action=="build" and road_authoring.start_build():return
	if not road_authoring.phase.is_empty() and action=="build":return
	if action=="clear": road_palette.clear();return
	if action=="level": road_palette.level_selection();return
	if action=="continue": road_palette.continue_selection(terrain);return
	if action in ["street_a","street_b"]: road_palette.select_street_end(0 if action=="street_a" else 1,terrain,road_palette.entrance_target.selected==1);return
	if action in ["start","finish"]:
		var origin:=camera.global_position
		var hit: Dictionary=structures.blocks.raycast_scene(origin,origin-camera.global_basis.z*48,3,[player.get_rid()])
		if hit.is_empty(): road_palette.status.text="Aim at nearby loaded terrain.";return
		if hit.has("cell") or not hit.collider is CollisionObject3D or (hit.collider.collision_layer&1)==0:
			road_palette.status.text="Road endpoints must be on terrain; a structure blocks the aim.";return
		road_palette.mark(action=="start",terrain.to_local(hit.position)+Vector3(0,0.25,0))
		return
	if action!="build": return
	if not road_palette.pending.is_empty(): road_palette.status.text="Wait for the submitted section to finish.";return
	var error: String=road_palette.validation_error()
	if not error.is_empty(): road_palette.status.text=error;return
	var a: Vector3=road_palette.start;var b: Vector3=road_palette.finish
	var extent: float=road_palette.width.value+road_palette.shoulder_width()
	var lo:=a.min(b)-Vector3(extent,road_palette.depth.value,extent)
	var hi:=a.max(b)+Vector3(extent,road_palette.clearance.value,extent)
	var protection_error:=_road_protection_error(AABB(lo,hi-lo))
	if not protection_error.is_empty():road_palette.status.text=protection_error;return
	var material: int=road_palette.material_id()
	var accepted: bool=terrain.construct_road_bed(a,b,road_palette.width.value,road_palette.depth.value,road_palette.clearance.value) if material==4 else terrain.construct_graded_bed(a,b,road_palette.width.value,road_palette.depth.value,road_palette.clearance.value,material,road_palette.shoulder_width())
	var kind: String="Road" if material==4 else "Foundation"
	if accepted: road_palette.track_submission(terrain)
	road_palette.status.text=("%s submitted · %s. Terrain grading has no block undo." % [kind,"temporary world" if temporary_world else "F5 saves world"]) if accepted else "%s not accepted; wait for terrain work to finish." % kind

func _road_protection_error(bounds: AABB) -> String:
	var protection:=AABB(terrain.to_local(player.global_position)-Vector3(0.4,0,0.4),Vector3(0.8,1.8,0.8))
	if bounds.grow(0.5).intersects(protection):return "Move clear of the road before building."
	if world_vehicle.overlaps_edit(terrain.global_transform*bounds.grow(0.5)):return "Move the vehicle clear before grading or paving."
	var transforms: Array[Transform3D]=[terrain.global_transform]
	var occupied: PackedByteArray=structures.overlap_mask(transforms,bounds.grow(0.5))
	if occupied.size()!=1 or occupied[0]!=0:return "Road bounds overlap a structure or unavailable building region."
	return ""

func _block_player_clear(target: Vector3i) -> bool:
	return not _brush_overlaps_player(Vector3(target)+Vector3.ONE*0.5,0.87)

func _terrain_placement_feedback() -> void:
	tool_view.place()

func _edit_structure(remove: bool) -> void:
	if not terrain.world_ready or not app_focused:
		return
	var hit := _structure_target(remove)
	if hit.is_empty():
		_show_lake_notice("Aim at a building block to remove it" if remove else "Aim at terrain or a building")
		return
	var target: Vector3i = hit.target
	if not remove and structure_prefab_index>=0:
		var asset: Resource = structure_prefabs[structure_prefab_index]
		if not asset.has_meta("frontage_version") and not asset.get_model_attachments().is_empty():
			var bounds: AABB=asset.placement_bounds(target,structure_rotation)
			if not _prefab_player_clear(bounds) or world_vehicle.overlaps_edit(bounds):
				_show_lake_notice("Move clear of the prefab before placing it");return
			_begin_direct_prefab(asset,target)
			return
		if not _prefab_allowed(asset,target):
			_show_lake_notice("Prefab blocked · clear existing blocks and move outside its bounds")
			return
		if asset.has_meta("frontage_version"):
			_begin_frontage_placement(asset,target)
			return
		if _place_combined_prefab(asset,target,structure_rotation):
			_show_lake_notice(_prefab_placement_text(asset))
		else: _show_lake_notice(construction_inventory.reason)
		player_hud.refresh()
		_prefab_preview_timer=0.0
		return
	if not remove and not _block_player_clear(target):
		_show_lake_notice("Block placement intersects the player")
		return
	var word := 0 if remove else structure_shape+(structure_rotation<<3)+(structure_material<<5)
	var placed := false
	if construction_inventory.place_block(structures.blocks,player_hud.inventory,target,word):
		placed = not remove
		world_attack.durability.forget(world_attack.block_key(target))
		_show_lake_notice("Block removed · F5 saves world" if remove else "Block placed · F5 saves world")
	else: _show_lake_notice(construction_inventory.reason)
	player_hud.refresh()
	if placed:tool_view.place()

func _survey_construction() -> void:
	if site_preparation.status=="running" or site_survey.busy or loading_active or shutdown_requested or not app_focused or player_hud.inventory_open or world_vehicle.driving or not structure_mode or model_tool.active or structure_prefab_index<0: return
	_survey_plan={}
	site_preview.clear()
	_survey_generation+=1
	var hit:=_structure_target(false)
	if hit.is_empty():
		construction_palette.show_survey("Aim at nearby terrain before starting a survey.");return
	var asset: Resource=structure_prefabs[structure_prefab_index]
	var target: Vector3i=hit.target
	var rotation:=structure_rotation
	var generation:=_survey_generation
	construction_palette.survey_busy=true
	_sync_construction_palette()
	var result: Dictionary=await site_survey.assess(terrain,asset,target,rotation)
	construction_palette.survey_busy=false
	_sync_construction_palette()
	if shutdown_requested or loading_active or not structure_mode or model_tool.active or world_vehicle.driving: return
	if generation!=_survey_generation or structure_prefab_index<0 or structure_prefabs[structure_prefab_index]!=asset or structure_rotation!=rotation:
		construction_palette.show_survey("Selection changed during survey. Survey the new placement again.");return
	if not result.ok:
		construction_palette.show_survey(result.reason);return
	var plan: Dictionary=preload("res://addons/structures/site_plan.gd").prepare(asset,target,rotation,result.grade)
	if not plan.ok: construction_palette.show_survey(plan.reason);return
	plan["epoch"]=terrain.epoch;plan["revision"]=terrain.density_revision;plan["generation"]=generation;plan["asset"]=asset
	_survey_plan=plan
	site_preview.show_plan(plan)
	construction_palette.preparation_status_button.show()
	construction_palette.prepare_button.text="Prepare foundation and street" if plan.paving_segments>0 else "Prepare stone foundation"
	construction_palette.show_survey("Origin X/Z: %d / %d · Rotation: %d°\nSuggested base Y: %d m (allowed %d–%d m)\nGround elevation: %.1f–%.1f m · %d foundation columns\n\nPrepare grades the whole rectangular site, including gaps,\nwith up to 8 m fill, 12 m cut and 8 m sloped fill shoulders.\nTerrain grading has no block undo. Buildings are not placed." % [target.x,target.z,rotation*90,result.grade,result.minimum_grade,result.maximum_grade,result.min_height,result.max_height,result.samples],true)
	if plan.paving_segments>0: construction_palette.survey_dialog.dialog_text+="\nThen paves the %d m street with asphalt before placement." % plan.street_width
	construction_palette.survey_dialog.dialog_text+="\nOutline: green foundation · orange fill · cyan asphalt."

func _site_protection_error(bounds: AABB) -> String:
	var protection:=AABB(terrain.to_local(player.global_position)-Vector3(0.4,0,0.4),Vector3(0.8,1.8,0.8))
	if bounds.grow(0.5).intersects(protection): return "Move outside the entire foundation and its shoulders."
	if world_vehicle.overlaps_edit(terrain.global_transform*bounds.grow(0.5)): return "Move the vehicle outside the entire site."
	var transforms: Array[Transform3D]=[terrain.global_transform]
	var occupied: PackedByteArray=structures.overlap_mask(transforms,bounds.grow(0.5))
	if occupied.size()!=1 or occupied[0]!=0: return "Site overlaps buildings, objects or unavailable structure data."
	return ""

func _site_selection_current() -> bool:
	return not _survey_plan.is_empty() and _survey_plan.generation==_survey_generation and structure_prefab_index>=0 and structure_prefabs[structure_prefab_index]==_survey_plan.asset and structure_rotation==_survey_plan.rotation

func _prepare_construction_site() -> void:
	# This action comes from the survey dialog, which can own native window focus.
	if site_preparation.status=="running" or loading_active or shutdown_requested or player_hud.inventory_open or world_vehicle.driving or not structure_mode or model_tool.active: return
	if not _site_selection_current(): construction_palette.show_survey("Selection changed; survey again.");return
	var accepted:=false
	if site_preparation.status=="stopped" and site_preparation.plan.get("generation",-1)==_survey_plan.generation and site_preparation.plan.get("target") == _survey_plan.target:
		accepted=site_preparation.resume(terrain,_site_protection_error)
	else:
		if terrain.epoch!=_survey_plan.epoch or terrain.density_revision!=_survey_plan.revision: construction_palette.show_survey("Terrain changed; survey again.");return
		accepted=site_preparation.begin(_survey_plan,terrain,_site_protection_error)
	if not accepted:
		construction_palette.show_survey(site_preparation.reason if not site_preparation.reason.is_empty() else "Preparation unavailable; survey again.",true);return
	construction_palette.survey_busy=true;_sync_construction_palette()
	construction_palette.prepare_button.disabled=true;construction_palette.stop_preparation_button.show()
	construction_palette.survey_dialog.dialog_text="Preparing foundation. Stop waits for the accepted edit to finish."

func _advance_site_preparation() -> void:
	if site_preparation.status!="running": return
	if loading_active or shutdown_requested or not structure_mode or model_tool.active or world_vehicle.driving or not _site_selection_current(): site_preparation.cancel()
	site_preparation.tick(terrain,_site_protection_error)
	construction_palette.survey_dialog.dialog_text="Foundation: %d / %d sections complete.\nAccepted terrain edits remain if preparation is stopped." % [site_preparation.completed,site_preparation.plan.segments.size()]
	if site_preparation.status=="running": return
	if site_preparation.status=="complete": road_palette.register_prepared_street(site_preparation.plan,terrain.epoch)
	construction_palette.survey_busy=false;_sync_construction_palette();construction_palette.stop_preparation_button.hide()
	var message: String="Foundation prepared at Y=%d. Place the selected prefab at this height; frontage support and clearance are checked again." % site_preparation.plan.target.y if site_preparation.status=="complete" else site_preparation.reason
	if site_preparation.status=="complete" and site_preparation.plan.get("paving_segments",0)>0: message+="\nRoad tools now offer Street end A / B for connecting roads."
	construction_palette.prepare_button.text="Resume foundation preparation"
	construction_palette.show_survey(message+"\nCompleted: %d / %d sections. Terrain grading has no block undo." % [site_preparation.completed,site_preparation.plan.segments.size()],site_preparation.status=="stopped" and _site_selection_current())
	construction_palette.place_prepared_button.visible=site_preparation.status=="complete" and _site_selection_current()
	construction_palette.place_prepared_button.disabled=false

func _cancel_site_actions() -> void:
	site_preparation.cancel()
	if _foundation_placement.get("from_dialog",false):
		construction_inventory.cancel_prefab()
		foundation_check.status="Placement cancelled";_foundation_placement={}

func _reopen_site_preparation() -> void:
	if not _site_selection_current(): construction_palette.show_survey("Selection changed; survey again.");return
	if site_preparation.status=="complete" and _preparation_matches_survey():
		construction_palette.show_survey("Foundation prepared at Y=%d. Placement will recheck terrain support and room clearance." % site_preparation.plan.target.y)
		construction_palette.place_prepared_button.show();construction_palette.place_prepared_button.disabled=false
	elif site_preparation.status=="stopped" and _preparation_matches_survey():
		construction_palette.prepare_button.text="Resume foundation preparation"
		construction_palette.show_survey(site_preparation.reason+"\nCompleted: %d / %d sections." % [site_preparation.completed,site_preparation.plan.segments.size()],true)
	else: construction_palette.survey_dialog.popup_centered()

func _preparation_matches_survey() -> bool:
	return not _survey_plan.is_empty() and site_preparation.plan.get("generation",-1)==_survey_plan.generation and site_preparation.plan.get("target")==_survey_plan.target and site_preparation.plan.get("asset")==_survey_plan.asset

func _place_prepared_site() -> void:
	if loading_active or shutdown_requested or player_hud.inventory_open or world_vehicle.driving or not structure_mode or model_tool.active or not _foundation_placement.is_empty(): return
	if site_preparation.status!="complete" or not _site_selection_current() or not _preparation_matches_survey() or terrain.epoch!=site_preparation.epoch:
		construction_palette.show_survey("Prepared site or selection changed. Survey again.");return
	# Terrain may have changed since grading; the full foundation check captures
	# its current revision and must succeed again before any blocks are inserted.
	var plan: Dictionary=site_preparation.plan
	if not _prefab_allowed(plan.asset,plan.target): construction_palette.show_survey("Placement blocked. Clear existing blocks and move outside the prefab.");return
	_begin_frontage_placement(plan.asset,plan.target,true)
	if _foundation_placement.is_empty():
		construction_palette.survey_dialog.dialog_text="Foundation check unavailable; wait for terrain, then retry.";return
	construction_palette.place_prepared_button.disabled=true
	construction_palette.survey_dialog.dialog_text="Checking foundation, underground support and room clearance…"

func _placement_notice(request: Dictionary,message: String,placed: bool=false) -> void:
	_show_lake_notice(message)
	if request.get("from_dialog",false):
		construction_palette.show_survey(message)
		construction_palette.place_prepared_button.visible=not placed and site_preparation.status=="complete" and _site_selection_current()
		construction_palette.place_prepared_button.disabled=false

func _begin_frontage_placement(asset: Resource,target: Vector3i,from_dialog: bool=false) -> void:
	if not _foundation_placement.is_empty(): _show_lake_notice("Checking foundation support…");return
	if foundation_check.begin(terrain,asset,target,structure_rotation):
		_foundation_placement={"asset":asset,"target":target,"rotation":structure_rotation,"index":structure_prefab_index,"from_dialog":from_dialog}
		_show_lake_notice("Checking foundation support…")
	else: _show_lake_notice("Foundation check unavailable; wait and place again")

func _begin_direct_prefab(asset: Resource,target: Vector3i) -> void:
	if not _foundation_placement.is_empty():_show_lake_notice("Wait for the current placement");return
	if construction_inventory.begin_prefab(structures.blocks,player_hud.inventory,asset,target,structure_rotation,structures.model_collections(),preload("res://addons/structures/construction_catalog.gd").recipes(),[model_tool.protection()]):
		_foundation_placement={"asset":asset,"target":target,"rotation":structure_rotation,"index":structure_prefab_index,"preparing":true,"require_support":false,"terrain_epoch":terrain.epoch,"terrain_revision":terrain.density_revision}
		_show_lake_notice("Preparing furnished building...")
	else:_show_lake_notice(construction_inventory.reason)

func _advance_frontage_placement() -> void:
	if _foundation_placement.is_empty(): return
	var request:=_foundation_placement
	var cancelled: bool=loading_active or shutdown_requested or (not app_focused and not request.get("from_dialog",false)) or player_hud.inventory_open or world_vehicle.driving or not structure_mode or model_tool.active or request.index!=structure_prefab_index or request.rotation!=structure_rotation or structure_prefabs[structure_prefab_index]!=request.asset
	if cancelled:
		foundation_check.status="Placement cancelled"
	if request.get("preparing",false):
		var bounds: AABB=request.asset.placement_bounds(request.target,request.rotation)
		if cancelled or (request.get("require_support",true) and foundation_check.status!="supported") or terrain.pending_edit or terrain.foreground_brush or not terrain.world_ready or terrain.epoch!=request.terrain_epoch or terrain.density_revision!=request.terrain_revision or not _prefab_player_clear(bounds) or world_vehicle.overlaps_edit(bounds):
			construction_inventory.cancel_prefab();_foundation_placement={}
			_placement_notice(request,"Placement changed during preparation; place again");return
		# Detach during publication so our own change signals do not cancel it.
		_foundation_placement={}
		var transaction_started:=Time.get_ticks_usec()
		var result: Dictionary=construction_inventory.advance_prefab([model_tool.protection()])
		terrain._record_stage("prefab transaction",(Time.get_ticks_usec()-transaction_started)/1000.0)
		for stage: String in result.get("timing",{}):
			terrain._record_stage("prefab "+stage,float(result.timing[stage])/1000.0)
		if result.ok and result.status=="preparing":
			_foundation_placement=request;return
		var feedback_started:=Time.get_ticks_usec()
		_placement_notice(request,_prefab_placement_text(request.asset) if result.ok else result.reason,result.ok)
		terrain._record_stage("prefab notice",(Time.get_ticks_usec()-feedback_started)/1000.0)
		var inventory_started:=Time.get_ticks_usec()
		# Free-editor placement and rejected transactions do not change inventory.
		# Avoid rebuilding item presentation and recipes when its revision is current.
		if player_hud.inventory.snapshot().revision!=player_hud.state.get("revision",-1):player_hud.refresh()
		_prefab_preview_timer=0.0
		terrain._record_stage("prefab inventory refresh",(Time.get_ticks_usec()-inventory_started)/1000.0)
		terrain._record_stage("prefab feedback",(Time.get_ticks_usec()-feedback_started)/1000.0);return
	foundation_check.tick(terrain)
	if foundation_check.status=="checking": return
	_foundation_placement={}
	if foundation_check.status!="supported": _placement_notice(request,foundation_check.status);return
	if terrain.pending_edit or terrain.foreground_brush or not terrain.world_ready or terrain.epoch!=foundation_check.epoch or terrain.density_revision!=foundation_check.revision or not _prefab_allowed(request.asset,request.target):
		_placement_notice(request,"Placement changed; place again");return
	if world_vehicle.overlaps_edit(request.asset.placement_bounds(request.target,request.rotation)):
		_placement_notice(request,"Move the vehicle clear before placing frontage");return
	if not request.asset.get_model_attachments().is_empty():
		if construction_inventory.begin_prefab(structures.blocks,player_hud.inventory,request.asset,request.target,request.rotation,structures.model_collections(),preload("res://addons/structures/construction_catalog.gd").recipes(),[model_tool.protection()]):
			request.preparing=true;request.terrain_epoch=terrain.epoch;request.terrain_revision=terrain.density_revision
			_foundation_placement=request;_show_lake_notice("Preparing furnished buildings...")
		else:_placement_notice(request,construction_inventory.reason)
		return
	if _place_combined_prefab(request.asset,request.target,request.rotation):
		_placement_notice(request,_prefab_placement_text(request.asset),true)
	else: _placement_notice(request,construction_inventory.reason)
	player_hud.refresh()
	_prefab_preview_timer=0.0

func _actor_collision_ready(bounds: AABB) -> bool:
	return terrain.is_collision_region_ready(bounds) and structures.is_collision_region_ready(bounds) and vegetation.is_collision_region_ready(bounds)

func _zombie_obstacle_target(zombie: CharacterBody3D) -> Node3D:
	if not _model_edit_available():return null
	var start:Vector3=zombie.global_position+Vector3.UP*1.1
	var offset:Vector3=player.global_position+Vector3.UP*1.1-start
	# Follow the routed approach on this storey. A ray aimed straight at an
	# upstairs recipient hits the lintel instead of the intervening door leaf.
	if zombie.navigation_target.is_finite():
		var routed:Vector3=zombie.navigation_target+Vector3.UP*1.1-start
		if Vector2(routed.x,routed.z).length()>0.05:
			offset=routed.normalized()*maxf(1.5,routed.length())
	var ray:=PhysicsRayQueryParameters3D.create(start,start+offset.limit_length(12.0),7,[player.get_rid()])
	var hit:=get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.get("collider")!=doors.collection:return null
	var identity:int=doors.collection.placement_for_body(hit.rid)
	if identity<=0 or doors.state.is_open(identity) or doors.collection.is_removal_protected(identity):return null
	var normal:Vector3=hit.normal;normal.y=0
	if normal.length_squared()<0.5:return null
	var obstacle=preload("res://addons/characters/runtime/obstacle_target.gd").new()
	obstacle.surface=doors.collection;obstacle.body_rid=hit.rid;obstacle.identity=identity
	var transform:PackedFloat32Array=doors.collection.get_instance(identity)
	if transform.size()!=12:obstacle.free();return null
	var base:Vector3=doors.collection.to_global(Vector3(transform[3],transform[7],transform[11]))
	var leaf_pose:=Transform3D(Basis(Vector3(transform[0],transform[4],transform[8]),Vector3(transform[1],transform[5],transform[9]),Vector3(transform[2],transform[6],transform[10])),Vector3(transform[3],transform[7],transform[11]))
	obstacle.shape_pose=doors.collection.global_transform*leaf_pose*Transform3D(Basis.IDENTITY,Vector3(.5,1.1,0))
	# Aim at the leaf centre, not an arbitrary ray hit near its jamb. The full
	# standing envelope must fit the doorway, and entrance steps define support.
	var centre:Vector3=obstacle.shape_pose.origin;centre.y=base.y
	normal=obstacle.shape_pose.basis.z.normalized()
	if (zombie.global_position-centre).dot(normal)<0:normal=-normal
	obstacle.contact_point=centre+Vector3.UP*1.1+normal*.07
	obstacle.approach_point=centre+normal*.55
	var support_ray:=PhysicsRayQueryParameters3D.create(obstacle.approach_point+Vector3.UP*.6,obstacle.approach_point-Vector3.UP*.8,7,[player.get_rid(),hit.rid])
	var support:Dictionary=get_world_3d().direct_space_state.intersect_ray(support_ray)
	if support.is_empty() or support.normal.y<.7072:obstacle.free();return null
	obstacle.approach_point.y=support.position.y+.04
	zombies.add_child(obstacle);obstacle.global_position=centre
	obstacle.validity=func():return _model_edit_available() and doors.collection.placement_for_body(obstacle.body_rid)==identity and doors.collection.get_instance(identity)==transform and not doors.state.is_open(identity) and not doors.collection.is_removal_protected(identity)
	obstacle.damage_callback=func(damage:float):
		var key:String="model:%s:%d"%[preload("res://addons/structures/door_catalog.gd").KEY,identity]
		var result:Dictionary=world_attack.durability.hit(key,world_attack.Durability.model_profile(preload("res://addons/structures/door_catalog.gd").KEY).health,maxi(1,int(roundf(damage))))
		if not result.ok:return
		terrain.changed_since_save=true
		if result.destroyed and doors.collection.remove_instances(PackedInt64Array([identity])):
			doors.state.forget(identity);world_attack.durability.forget(key)
			_show_lake_notice("Zombie broke a wooden door")
	return obstacle

func _physics_process(delta: float) -> void:
	zombies.update(delta,player.global_position,not loading_active and not shutdown_requested and terrain.world_ready and not terrain.pending_edit and not session_menu.visible_ui() and not player_hud.inventory_open and not world_vehicle.driving and app_focused,not fly)
	actors.update_simulation(delta,terrain.focus,not loading_active and not shutdown_requested and terrain.world_ready and not terrain.pending_edit,_actor_collision_ready)
	if world_vehicle.driving:
		return # The bound vehicle owns terrain focus and physics while occupied.
	super._physics_process(delta)

func _process(delta: float) -> void:
	var frame_begin:=Time.get_ticks_usec()
	world_interaction.update(self,delta)
	terrain._record_stage("world interaction",(Time.get_ticks_usec()-frame_begin)/1000.0)
	var section_begin:=Time.get_ticks_usec()
	road_palette.poll_submission(terrain)
	site_preview.visible=site_preview.vertices>0 and _site_selection_current() and _survey_plan.get("epoch",-1)==terrain.epoch and structure_mode and not model_tool.active and not world_vehicle.driving and not loading_active and not player_hud.inventory_open
	var frontage_result: Dictionary=prefab_library.poll_frontage()
	if not frontage_result.is_empty(): _accept_composed_prefab(frontage_result)
	_advance_frontage_placement()
	_advance_site_preparation()
	terrain._record_stage("world authoring",(Time.get_ticks_usec()-section_begin)/1000.0)
	section_begin=Time.get_ticks_usec()
	world_vehicle.update(self,delta)
	terrain._record_stage("world vehicle",(Time.get_ticks_usec()-section_begin)/1000.0)
	if world_vehicle.driving!=_vehicle_ui_active:
		_vehicle_ui_active=world_vehicle.driving
		player_hud.visible=not _vehicle_ui_active;player_hud.enabled=not _vehicle_ui_active
		var crosshair=help.get_parent().get_node_or_null("Crosshair")
		if crosshair!=null: crosshair.visible=not _vehicle_ui_active
		if _vehicle_ui_active:
			_walking_help=help.text
			help.text="W / S  Accelerate / Brake or reverse    A / D  Steer    Space  Handbrake    Shift  Boost\nE  Exit when stopped    R  Reset vehicle    Esc  Release mouse\nF5 Save · reload on foot beside the parked vehicle. Cosmetic dents are not saved."
		else: help.text=_walking_help
	section_begin=Time.get_ticks_usec()
	super._process(delta)
	terrain._record_stage("base controller",(Time.get_ticks_usec()-section_begin)/1000.0)
	section_begin=Time.get_ticks_usec()
	road_palette.panel.visible=session_menu.workspace and session_menu.current_page=="Roads" and session_menu.developer
	road_preview.visible=not world_vehicle.driving and not structure_mode and not model_tool.active and not loading_active and not shutdown_requested and not player_hud.inventory_open
	water_camera.update()
	terrain._record_stage("world presentation",(Time.get_ticks_usec()-section_begin)/1000.0)
	section_begin=Time.get_ticks_usec()
	pickups.update_view(delta,player.global_position,not loading_active and not shutdown_requested)
	terrain._record_stage("world pickups",(Time.get_ticks_usec()-section_begin)/1000.0)
	terrain._record_stage("controller process",(Time.get_ticks_usec()-frame_begin)/1000.0)
	ground_preview.update(self,delta)
	_update_prefab_preview(delta)
	model_tool.update(delta,_model_edit_available())
	tool_view.visible=not session_menu.visible_ui() and not player_hud.inventory_open and not world_vehicle.driving
	if structures.blocks != null:
		structures.blocks.set_focus(player.position)
		if terrain.world_ready and (not temporary_world or terrain.backend.readonly_snapshot) and not shutdown_requested:
			if structures.enable_region_paging(terrain.backend.snapshot_codec):
				structures.step_region_paging(player.global_position)
		structures.set_model_focus(player.global_position)
	_telemetry_time += delta
	if _telemetry_time >= 0.5 and vegetation.ready_to_render:
		_telemetry_time = 0.0
		var activity: String = "Updating terrain…" if terrain.pending_edit else "Explore · Sculpt · Build"
		var building_stream: Dictionary = structures.blocks.streaming_stats()
		var building_collision: Dictionary = structures.blocks.collision_stats()
		var paging: Dictionary = structures.region_paging_stats()
		if paging.active and paging.pending>0:
			activity="Loading nearby buildings…"
		if paging.active and paging.failed_reads>0:
			activity="Building region unavailable · retrying"
		if building_collision.pending_chunks>0 or building_collision.unresolved_mesh_chunks>0:
			activity="Preparing nearby building collision…"
		if structure_motion_blocked:
			activity="Waiting for building collision ahead…"
		if building_stream.budget_blocked_chunks>0:
			activity="Building detail limit · %d chunks deferred" % building_stream.budget_blocked_chunks
		if Time.get_ticks_msec() < _lake_notice_until:
			activity = _lake_notice
		if world_vehicle.driving:
			activity="Waiting for terrain/building collision…" if world_vehicle.car.streaming.waiting else "Driving · %.0f km/h · E exit when stopped" % world_vehicle.car.speed_kph
		telemetry.text = "%d FPS  ·  %s trees  ·  %d cells\n%s" % [Engine.get_frames_per_second(), str(vegetation.renderer.roots.size()), ecosystem.resident.size(), activity]
		if actors.pool!=null and actor_authoring.selected_identity!=0:
			var actor_handle: int=actors.store.resolve_identity(actor_authoring.selected_identity)
			var actor_order: Dictionary=actors.orders.get_target(actor_authoring.selected_identity)
			telemetry.text+=("\nPatrol route: " if actor_order.get("patrol",false) else "\nActor route: ")+str(actors.pool.navigation_status(actor_handle).state).replace("_"," ")
		if actors.pool!=null and session_menu.workspace and session_menu.current_page=="Actors":telemetry.text+="\nJ Place actor · Shift+J Remove actor\nK Select / send · Shift+K Stop"
	terrain._record_stage("world process",(Time.get_ticks_usec()-frame_begin)/1000.0)

func _harvest_aimed_tree() -> bool:
	if vegetation.trunk_collision==null or terrain.pending_edit: return false
	var origin:=camera.global_position
	# Native scene ray respects terrain, building, vehicle and trunk occlusion.
	var hit: Dictionary=structures.blocks.raycast_scene(origin,origin-camera.global_basis.z*2.5,7,[player.get_rid()])
	if hit.is_empty() or hit.collider!=vegetation.trunk_collision: return false
	var id: int=vegetation.trunk_collision.placement_for_body(hit.rid)
	var result: Dictionary=ecosystem.harvest_root(id,player_hud.inventory)
	if result.ok: player_hud.refresh()
	_show_lake_notice(result.reason)
	return true

func _pickup_reachable(point: Vector3) -> bool:
	var query:=PhysicsRayQueryParameters3D.create(camera.global_position,point,7,[player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _remove_actor(identity: int) -> bool:
	var handle: int=actors.store.resolve_identity(identity)
	if handle==0 or not actors.store.despawn(handle):return false
	actors.orders.clear_target(identity)
	world_attack.durability.forget("actor:%d"%identity)
	if actor_authoring.selected_identity==identity:
		actor_authoring.selected_identity=0;actor_authoring.selected_epoch=-1
		if actors.renderer!=null:actors.renderer.set_selection_marker(actors.selection_marker,0)
	actors.select_near(terrain.focus)
	terrain.changed_since_save=true
	return true

func _place_inventory_model(history: RefCounted, collection: Node3D, transforms: PackedFloat32Array, protection: AABB, costs: PackedInt64Array) -> int:
	if not _model_edit_available():
		model_tool.placement_failure="World interaction unavailable"
		return 0
	var id: int=construction_inventory.place_model(history,collection,player_hud.inventory,transforms,protection,costs)
	model_tool.placement_failure=construction_inventory.reason
	player_hud.refresh()
	return id

func _remove_inventory_model(history: RefCounted, collection: Node3D, identity: int) -> bool:
	if not _model_edit_available():
		model_tool.placement_failure="World interaction unavailable";return false
	var recipes: Dictionary=preload("res://addons/structures/construction_catalog.gd").salvage_recipes()
	for key: String in recipes:
		if structures.model(key)==collection:
			var removed: bool=construction_inventory.salvage_model(history,collection,player_hud.inventory,identity,recipes[key])
			if removed and collection==doors.collection:doors.state.forget(identity)
			model_tool.placement_failure=construction_inventory.reason;player_hud.refresh();return removed
	var removed: bool=history.erase(collection,identity)
	if removed and collection==doors.collection:doors.state.forget(identity)
	model_tool.placement_failure="Object removed; no salvage recipe" if removed else "Object removal rejected"
	return removed

func _model_edit_available() -> bool:
	return not world_vehicle.driving and not loading_active and not shutdown_requested and not benchmark_enabled and not player_hud.inventory_open and app_focused and terrain.world_ready and not terrain.pending_edit

func _vehicle_interaction_available() -> bool:
	return not loading_active and not shutdown_requested and not benchmark_enabled and not player_hud.inventory_open and app_focused and terrain.world_ready and not terrain.pending_edit and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED

func _drop_inventory_supply(slot: int, revision: int, count: int=1) -> void:
	var result := {"ok":false,"reason":"Stand on foot in a ready world to drop supplies"}
	if (player_hud.inventory_open or Input.mouse_mode==Input.MOUSE_MODE_CAPTURED) and app_focused and not fly and not loading_active and not shutdown_requested and terrain.world_ready and not terrain.pending_edit and not world_vehicle.driving:
		var forward := -player.global_basis.z
		forward.y=0;forward=forward.normalized()
		for offset: float in [0.0,0.55,-0.55,1.1,-1.1]:
			var start := player.global_position+forward*1.2+Vector3.UP*1.5+player.global_basis.x*offset
			var query := PhysicsRayQueryParameters3D.create(start,start-Vector3.UP*3.0,3,[player.get_rid()])
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			result.reason="No reachable clear ground in front of the player"
			if not hit.is_empty() and Vector3(hit.normal).y>=0.7:
				var point: Vector3=hit.position+Vector3.UP*0.2
				var bounds:=AABB(point-Vector3.ONE*0.2,Vector3.ONE*0.4)
				if terrain.player_region_ready(point) and structures.is_collision_region_ready(bounds) and vegetation.is_collision_region_ready(bounds) and _pickup_reachable(point):
					var shape:=BoxShape3D.new();shape.size=Vector3.ONE*0.35
					var overlap:=PhysicsShapeQueryParameters3D.new();overlap.shape=shape;overlap.transform=Transform3D(Basis.IDENTITY,point);overlap.collision_mask=7
					var clear:=get_world_3d().direct_space_state.intersect_shape(overlap,1).is_empty()
					for store: RefCounted in pickups.stores.values():
						var nearby: Dictionary=store.query_sphere(pickups.to_local(point),0.5,1,64)
						clear=clear and nearby.ok and nearby.complete and nearby.ids.is_empty()
					if clear: result=pickups.drop_stack(player_hud.inventory,slot,revision,pickups.to_local(point),count)
			if result.ok:break
	player_hud.message.text=result.reason
	_show_lake_notice(result.reason)
	player_hud.refresh()

func _place_combined_prefab(asset: Resource,target: Vector3i,rotation: int) -> bool:
	return construction_inventory.place_prefab(structures.blocks,player_hud.inventory,asset,target,rotation,structures.model_collections(),preload("res://addons/structures/construction_catalog.gd").recipes(),[model_tool.protection()])

func _prefab_placement_text(asset: Resource) -> String:
	var attached: bool=not construction_inventory.prefab_transaction.model_counts(asset).is_empty()
	return "%s placed - F5 saves%s" % [asset.resource_name,"; combined undo unavailable" if attached else ""]

func _update_loading() -> void:
	if not loading_active:return
	super._update_loading()
	if not loading_active:player_hud.equip_first_tool_if_unselected()

func _additional_loading_diagnostics() -> Dictionary:
	# Constant-sized summaries. Never copy instance buffers or scan the world.
	return {
		"trees":vegetation.statistics(),
		"ground_cover":{"enabled":ground_cover.is_processing(),"wanted_regions":ground_cover._wanted.size(),"resident_regions":ground_cover.resident.size(),"requested":ground_cover._requests.size(),"pending":ground_cover._pending.size(),"dirty":ground_cover._dirty.size(),"rejected_batches":ground_cover.rejected_batches},
		"water":lakes.statistics() if lakes.water!=null else {"state":"not_initialized"},
		"structures":{"asset_collections":structures._models.size(),"paging_failures":structures._model_paging_failures,"last_failure":structures._model_paging_last_failure,"paging":model_paging.last_state if model_paging!=null else {"active":false}}
	}

# Cached water surfaces must be visible before entering the playable world.
func _additional_loading_ready() -> bool:
	# Terrain readiness alone does not cover asynchronously admitted model proxies.
	# Keep a small departure margin available before restoring player input.
	var arrival_bounds:=AABB(player.global_position-Vector3(2,2,2),Vector3(4,5,4))
	if not structures.is_collision_region_ready(arrival_bounds) or not vegetation.is_collision_region_ready(arrival_bounds):
		loading_stage_percent=75;loading_stage_text="Preparing nearby object collision"
		loading_work_text="Waiting for building / tree collision within 2 m of the player · "+loading_work_text
		return false
	# Match the nearby model acceptance radius; distant world continues streaming.
	var visual_bounds:=AABB(player.global_position-Vector3(128,128,128),Vector3(256,256,256))
	if not structures.is_model_render_region_ready(visual_bounds):
		loading_stage_percent=82;loading_stage_text="Loading nearby buildings and objects"
		loading_work_text="Waiting for model proxies within 128 m of the player · "+loading_work_text
		return false
	if lakes.water==null:
		loading_stage_percent=90;loading_stage_text="Loading water sources";return false
	var state:Dictionary=lakes.statistics()
	if not state.render_ready or state.ready!=state.lakes:
		loading_stage_percent=90
		loading_work_text="Water: lakes %d/%d ready · %d regions pending · %d surfaces dirty · %d staged meshes"%[state.ready,state.lakes,state.pending_regions,state.dirty_meshes,state.staged_meshes]
		loading_stage_text="Loading water - %d regions remaining"%int(state.pending_regions) if state.pending_regions>0 else "Building water surfaces - %d remaining"%int(state.dirty_meshes)
		return false
	return true

func _populate_settlement_actors() -> Dictionary:
	var reason: String=actor_authoring.unavailable(self)
	if not reason.is_empty():
		_show_lake_notice(reason);return {"ok":false,"reason":reason}
	var result: Dictionary=preload("res://addons/world_runtime/settlement_actors.gd").populate(self)
	_show_lake_notice(result.reason)
	return result

func _make_world_locations()->Control:
	var view=preload("res://demo/world_locations.gd").new();view.game=self;return view
