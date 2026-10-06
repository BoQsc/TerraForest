extends "res://demo/controller.gd"
const Vegetation = preload("res://addons/vegetation/vegetation_world.gd")
const Ecosystem = preload("res://addons/world_ecosystem/world_ecosystem.gd")
const Lakes = preload("res://addons/volumetric_water/lake_world.gd")
const Persistence = preload("res://addons/world_runtime/world_persistence.gd")
const Structures = preload("res://addons/structures/structures_world.gd")
var persistence = Persistence.new()
var pickups = preload("res://addons/world_runtime/material_pickups.gd").new()
var player_pose: RefCounted
var world_vehicle=preload("res://addons/vehicle_runtime/world_vehicle.gd").new()
var _vehicle_ui_active:=false
var _walking_help:=""
var _saved_pose:=PackedByteArray()
var _restored_pose: Dictionary={}
var vegetation = Vegetation.new()
var ecosystem = Ecosystem.new()
var lakes = Lakes.new()
var water_camera=preload("res://addons/volumetric_water/water_camera.gd").new()
var structures = Structures.new()
var player_hud=preload("res://addons/player_runtime/player_hud.gd").new()
var construction_inventory=preload("res://addons/player_runtime/construction_inventory.gd").new()
var mining_rewards=preload("res://addons/player_runtime/mining_rewards.gd").new()
var model_tool = preload("res://addons/structures/model_tool.gd").new()
var structure_mode := false
var construction_palette=preload("res://addons/structures/construction_palette.gd").new()
var road_palette=preload("res://addons/volumetric_terrain/road_palette.gd").new()
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

func _ready() -> void:
	construction_inventory.gameplay="--gameplay-construction" in OS.get_cmdline_user_args()
	player_hud.gameplay_construction=construction_inventory.gameplay
	tree_exiting.connect(prefab_library.shutdown_frontage)
	add_child(world_vehicle)
	add_child(pickups)
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
	if not player_hud.prepare() or not persistence.register_component("player_loadout", player_hud.capture_snapshot, player_hud.restore_snapshot, player_hud.inventory, player_hud.default_loadout):
		push_error("Player loadout persistence initialization failed")
		get_tree().quit(2)
		return
	if not persistence.register_component("pending_rewards",player_hud.reward_inbox.capture_storage_snapshot,player_hud.reward_inbox.restore_storage_snapshot,player_hud.reward_inbox,player_hud.reward_inbox.capture_storage_snapshot()):
		push_error("Pending reward persistence initialization failed")
		get_tree().quit(2)
		return
	if construction_inventory.gameplay and not mining_rewards.attach(terrain,player_hud):
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
	if not structures_ready or not lakes.prepare() or not persistence.register_component("structures", structures.capture_storage_snapshot, structures.restore_storage_snapshot, structures.snapshot_validator(), structures.empty_snapshot()) or not persistence.register_component("volumetric_water", lakes.capture_snapshot, lakes.restore_snapshot, lakes.snapshot_validator(), lakes.empty_snapshot()) or not persistence.enable_region_structures(true) or persistence.attach(terrain) != OK:
		push_error("World persistence initialization failed")
		get_tree().quit(2)
		return
	_setup_prefabs()
	terrain.density_batch_ready.connect(foundation_check.receive)
	structures.blocks.configure_history(16*1024*1024,128)
	structures.blocks.configure_streaming(true,384,256,64*1024*1024,32*1024*1024)
	structures.model("architecture/metal_beam/v1").configure_collision(beam.get_aabb(),64,512,8)
	door_models.configure_compound_collision(doorway.get_meta("collision_boxes"),64,512,8,1536,24)
	terrain.nearby_first = true
	pending_spawn = Vector3(800, 0, 1310)
	terrain.focus = pending_spawn
	super._ready()
	add_child(model_tool)
	model_tool.gameplay=construction_inventory.gameplay
	model_tool.paid_placement=_place_inventory_model
	model_tool.availability=_model_edit_available
	model_tool.configure(camera,player,[
		{"title":"Metal beam","mesh":beam,"collection":structures.model("architecture/metal_beam/v1"),"scale":Vector3(4,0.2,0.2),"costs":PackedInt64Array([104,4]),"cost_label":"4 metal"},
		{"title":"Floor panel","mesh":beam,"collection":structures.model("architecture/metal_beam/v1"),"scale":Vector3(4,0.25,4),"costs":PackedInt64Array([104,8]),"cost_label":"8 metal"},
		{"title":"Doorway","mesh":doorway,"collection":door_models,"scale":Vector3.ONE,"costs":PackedInt64Array([103,8]),"cost_label":"8 concrete"}],help.get_parent(),structures.blocks)
	model_tool.notice.connect(_show_lake_notice)
	player_hud.temporary_world=temporary_world
	add_child(player_hud)
	add_child(construction_palette)
	add_child(road_palette)
	road_palette.action_requested.connect(_road_action)
	terrain.add_child(road_preview)
	terrain.add_child(site_preview)
	road_palette.selection_changed.connect(_update_road_preview)
	construction_palette.configure(structure_prefabs)
	construction_palette.selection_requested.connect(_construction_selection)
	construction_palette.capture_requested.connect(_capture_construction)
	construction_palette.supply_requested.connect(_place_material_supply)
	construction_palette.stack_requested.connect(_stack_construction)
	construction_palette.frontage_requested.connect(_frontage_construction)
	construction_palette.frontage_sources_requested.connect(_frontage_sources_construction)
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
	structures.changed.connect(func(): terrain.changed_since_save=true)
	ecosystem.harvested.connect(func(): terrain.changed_since_save=true)
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
	ecosystem.name = "Ecosystem"
	ecosystem.terrain = terrain
	ecosystem.vegetation = vegetation
	ecosystem.camera = camera
	ecosystem.structures = structures
	ecosystem.water = lakes
	add_child(ecosystem)
	lakes.name = "Lakes"
	lakes.terrain = terrain
	add_child(lakes)
	add_child(water_camera)
	water_camera.configure(camera,lakes)
	lakes.lake_ready.connect(func(_id: int): _show_lake_notice("Lake ready · temporary world" if temporary_world else "Lake ready · F5 saves world"))
	lakes.lake_failed.connect(func(_id: int, code: int): _show_lake_notice("Lake rejected (%d): open basin or blocked seed" % code))

func _show_lake_notice(text: String) -> void:
	_sync_construction_palette()
	_lake_notice = text
	_lake_notice_until = Time.get_ticks_msec()+6000
	_message(text)

func _capture_player_pose() -> PackedByteArray:
	if world_vehicle.driving:
		var feet:=world_vehicle.safe_exit_position(self)
		var captured: PackedByteArray=player_pose.encode(feet,wrapf(yaw,-PI,PI),pitch,false,player_hud.active_item) if feet.is_finite() else PackedByteArray()
		# Reject the compound save if no safe on-foot restore point exists.
		return captured if not captured.is_empty() else PackedByteArray([0])
	if not loading_active and not waiting_spawn and not world_vehicle.driving:
		var captured: PackedByteArray=player_pose.encode(player.position,wrapf(yaw,-PI,PI),pitch,fly,player_hud.active_item)
		if not captured.is_empty(): _saved_pose=captured
	return _saved_pose

func _restore_player_pose(data: PackedByteArray) -> bool:
	var decoded: Dictionary=player_pose.decode(data)
	if not decoded.ok: return false
	_saved_pose=data
	_restored_pose=decoded
	return true

func _terrain_initialized(text: String) -> void:
	if _restored_pose.has("position"):
		pending_spawn=_restored_pose.position
		spawn_override_y=pending_spawn.y
		fly=_restored_pose.fly
		yaw=_restored_pose.yaw
		pitch=_restored_pose.pitch
		player.rotation.y=yaw
		camera.rotation.x=pitch
		var item: int=_restored_pose.tool
		structure_mode=item in [3,4]
		model_tool.set_active(item==4)
		if item==1: tool=3
		elif item==2: tool=1
		_sync_player_tool()
	else:
		pending_spawn=Vector3(800,0,1310)
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
	var frontage=ClassDB.instantiate("NativeBlockPrefab")
	var cottage: Resource=load("res://addons/structures/prefabs/brick_cottage.tres")
	if frontage.compose_frontage([cottage],2,8,3,1703):
		frontage.resource_name="Street frontage · 4 cottages (ungraded)"
		frontage.set_meta("frontage_version",1)
		frontage.set_meta("street_width",8);frontage.set_meta("frontage_gap",3)
		structure_prefabs.append(frontage)
		frontage.changed.connect(_invalidate_prefab_preview)
	structures.blocks.changed.connect(_invalidate_prefab_preview)
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
	if signature != _prefab_preview_signature:
		_prefab_preview_clear=structures.blocks.can_place_prefab(asset,hit.target,structure_rotation)
		_prefab_preview_signature=signature
	prefab_preview.position=bounds.position
	prefab_preview.scale=bounds.size
	_prefab_preview_material.albedo_color=Color("66f2b3") if _prefab_preview_clear and _prefab_player_clear(bounds) else Color("ff705f")
	if asset.has_meta("frontage_version") and _prefab_preview_clear and _prefab_player_clear(bounds):
		_prefab_preview_material.albedo_color=Color("edc66a") # Support is checked on placement.
	prefab_preview.show()

func _message(text: String) -> void:
	super._message(text)
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
	var id: int = lakes.add_lake(center - Vector3(16,16,16), Vector3i(32,20,32), 1.0, center.y-3.0, center-Vector3(0,6,0))
	if id == 0:
		return 0
	if not terrain.sculpt_sphere(center, 12.0):
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
			var sky_material := ProceduralSkyMaterial.new()
			sky_material.sky_top_color = Color("527b9a")
			sky_material.sky_horizon_color = Color("c4d6d8")
			sky_material.ground_bottom_color = Color("303d37")
			sky_material.ground_horizon_color = Color("c4d6d8")
			sky.sky_material = sky_material
			environment.sky = sky
			environment.background_mode = Environment.BG_SKY
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
	help.text=help.text.replace("B  Terrain / Blocks", "B  Terrain / Blocks    M  Objects    E  Collect / Harvest")
	help.text+="\nV  Place vehicle    E  Enter / exit stopped vehicle    F5  Save world and vehicle"
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

func _equip_player_tool(item: int) -> void:
	if item not in player_hud.CATALOG: return
	_set_player_tool_mode(item==3 or item==4,item==4,3 if item==1 else (1 if item==2 else tool))

func _sync_player_tool() -> void:
	_sync_construction_palette()
	player_hud.show_active_tool(4 if model_tool.active else (3 if structure_mode else (1 if tool==3 else (2 if tool==1 else 0))))

func _sync_construction_palette() -> void:
	construction_palette.synchronize(structure_mode and not model_tool.active,structure_shape,structure_material,structure_rotation,structure_prefab_index)
	if construction_palette.archive_button!=null:
		construction_palette.archive_button.disabled=structure_prefab_index<0 or not prefab_library.owns(structure_prefabs[structure_prefab_index])

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
		var result: Dictionary=prefab_library.capture(structures.blocks,title)
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

func _frontage_sources_construction(indices: PackedInt32Array,lots: int,width: int,gap: int,seed: int,title: String) -> void:
	if loading_active or shutdown_requested or benchmark_enabled or player_hud.inventory_open or not structure_mode or model_tool.active: return
	var sources: Array[Resource]=[]
	for index in indices:
		if index<0 or index>=structure_prefabs.size(): construction_palette.capture_status.text="Building selection changed; reopen the street tool";return
		sources.append(structure_prefabs[index])
	var result: Dictionary=prefab_library.begin_frontage_sources(sources,lots,width,gap,seed,title)
	construction_palette.capture_status.text="Generating mixed frontage…" if result.ok else result.reason

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
	_clear_motion()
	stroke_buffer.clear();held_previous=false
	model_tool.set_active(objects)
	structure_mode=building
	tool=terrain_tool
	_sync_player_tool()
	_show_lake_notice(player_hud.CATALOG.get(player_hud.active_item,"Terrain editing"))
	return true

func _unhandled_input(event: InputEvent) -> void:
	if player_hud.inventory_open: return
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
	# Object mode owns E. Do not enter a vehicle, harvest or collect supplies
	# while the player is using the advertised select-object action.
	if model_tool.active and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_E:
		if not loading_active and not shutdown_requested and not benchmark_enabled and app_focused and terrain.world_ready and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
			model_tool.handle_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo and not loading_active and not shutdown_requested and app_focused and not fly and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		if event.physical_keycode==KEY_V:
			_show_lake_notice(world_vehicle.spawn(self));return
		if event.physical_keycode==KEY_E and world_vehicle.enter(self):
			_clear_motion();_show_lake_notice("Driving · E exit when stopped · Space brake");return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode==KEY_E and not fly:
		if not loading_active and not shutdown_requested and app_focused and terrain.world_ready and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
			if construction_inventory.gameplay and _harvest_aimed_tree(): return
			var collected: Dictionary=pickups.collect_near(player.global_position+Vector3(0,0.5,0),player_hud.inventory,_pickup_reachable)
			if collected.ok: player_hud.refresh()
			_show_lake_notice(collected.reason)
		return
	if not loading_active and not benchmark_enabled:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode==KEY_M:
				_set_player_tool_mode(true,not model_tool.active,tool)
				return
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
					_show_lake_notice("%s · %d°" % [structure_prefabs[structure_prefab_index].resource_name,structure_rotation*90] if structure_prefab_index>=0 else "%s · %s · %d°" % [["Cube","Slab","Stairs","Slope","Post","Sphere"][structure_shape-1],["Brick","Wood","Concrete","Metal"][structure_material],structure_rotation*90])
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
	var hit: Dictionary = structures.blocks.raycast_scene(origin,origin-camera.global_basis.z*48,3,[player.get_rid()])
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
	if not road_palette.has_start and not road_palette.has_finish:
		road_preview.clear();return
	var a: Vector3=road_palette.start if road_palette.has_start else road_palette.finish
	var b: Vector3=road_palette.finish if road_palette.has_finish else a
	road_preview.update_selection(a,b,road_palette.width.value,road_palette.depth.value,road_palette.validation_error().is_empty(),road_palette.clearance.value,road_palette.shoulder_width())

func _road_action(action: String) -> void:
	if loading_active or shutdown_requested or benchmark_enabled or not app_focused or not terrain.world_ready or player_hud.inventory_open or structure_mode or model_tool.active: return
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
	var protection:=AABB(terrain.to_local(player.global_position)-Vector3(0.4,0,0.4),Vector3(0.8,1.8,0.8))
	if AABB(lo,hi-lo).grow(0.5).intersects(protection): road_palette.status.text="Move clear of the road before building.";return
	if world_vehicle.overlaps_edit(terrain.global_transform*AABB(lo,hi-lo).grow(0.5)):
		road_palette.status.text="Move the vehicle clear before grading or paving.";return
	var transforms: Array[Transform3D]=[terrain.global_transform]
	var occupied: PackedByteArray=structures.overlap_mask(transforms,AABB(lo,hi-lo).grow(0.5))
	if occupied.size()!=1 or occupied[0]!=0:
		road_palette.status.text="Road bounds overlap a structure or unavailable building region. Choose a clear route.";return
	var material: int=road_palette.material_id()
	var accepted: bool=terrain.construct_road_bed(a,b,road_palette.width.value,road_palette.depth.value,road_palette.clearance.value) if material==4 else terrain.construct_graded_bed(a,b,road_palette.width.value,road_palette.depth.value,road_palette.clearance.value,material,road_palette.shoulder_width())
	var kind: String="Road" if material==4 else "Foundation"
	if accepted: road_palette.track_submission(terrain)
	road_palette.status.text=("%s submitted · %s. Terrain grading has no block undo." % [kind,"temporary world" if temporary_world else "F5 saves world"]) if accepted else "%s not accepted; wait for terrain work to finish." % kind

func _block_player_clear(target: Vector3i) -> bool:
	return not _brush_overlaps_player(Vector3(target)+Vector3.ONE*0.5,0.87)

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
		if not _prefab_allowed(asset,target):
			_show_lake_notice("Prefab blocked · clear existing blocks and move outside its bounds")
			return
		if asset.has_meta("frontage_version"):
			_begin_frontage_placement(asset,target)
			return
		if construction_inventory.place_prefab(structures.blocks,player_hud.inventory,asset,target,structure_rotation):
			_show_lake_notice("%s placed · F5 saves world" % asset.resource_name)
		else: _show_lake_notice(construction_inventory.reason)
		player_hud.refresh()
		_prefab_preview_timer=0.0
		return
	if not remove and not _block_player_clear(target):
		_show_lake_notice("Block placement intersects the player")
		return
	var word := 0 if remove else structure_shape+(structure_rotation<<3)+(structure_material<<5)
	if construction_inventory.place_block(structures.blocks,player_hud.inventory,target,word):
		_show_lake_notice("Block removed · F5 saves world" if remove else "Block placed · F5 saves world")
	else: _show_lake_notice(construction_inventory.reason)
	player_hud.refresh()

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

func _advance_frontage_placement() -> void:
	if _foundation_placement.is_empty(): return
	var request:=_foundation_placement
	if loading_active or shutdown_requested or (not app_focused and not request.get("from_dialog",false)) or player_hud.inventory_open or world_vehicle.driving or not structure_mode or model_tool.active or request.index!=structure_prefab_index or request.rotation!=structure_rotation or structure_prefabs[structure_prefab_index]!=request.asset:
		foundation_check.status="Placement cancelled"
	foundation_check.tick(terrain)
	if foundation_check.status=="checking": return
	_foundation_placement={}
	if foundation_check.status!="supported": _placement_notice(request,foundation_check.status);return
	if terrain.pending_edit or terrain.foreground_brush or not terrain.world_ready or terrain.epoch!=foundation_check.epoch or terrain.density_revision!=foundation_check.revision or not _prefab_allowed(request.asset,request.target):
		_placement_notice(request,"Placement changed; place again");return
	if world_vehicle.overlaps_edit(request.asset.placement_bounds(request.target,request.rotation)):
		_placement_notice(request,"Move the vehicle clear before placing frontage");return
	if construction_inventory.place_prefab(structures.blocks,player_hud.inventory,request.asset,request.target,request.rotation):
		_placement_notice(request,"%s placed · F5 saves world" % request.asset.resource_name,true)
	else: _placement_notice(request,construction_inventory.reason)
	player_hud.refresh()
	_prefab_preview_timer=0.0

func _physics_process(delta: float) -> void:
	if world_vehicle.driving:
		return # The bound vehicle owns terrain focus and physics while occupied.
	super._physics_process(delta)

func _process(delta: float) -> void:
	var frame_begin:=Time.get_ticks_usec()
	road_palette.poll_submission(terrain)
	site_preview.visible=site_preview.vertices>0 and _site_selection_current() and _survey_plan.get("epoch",-1)==terrain.epoch and structure_mode and not model_tool.active and not world_vehicle.driving and not loading_active and not player_hud.inventory_open
	var frontage_result: Dictionary=prefab_library.poll_frontage()
	if not frontage_result.is_empty(): _accept_composed_prefab(frontage_result)
	_advance_frontage_placement()
	_advance_site_preparation()
	world_vehicle.update(self,delta)
	if world_vehicle.driving!=_vehicle_ui_active:
		_vehicle_ui_active=world_vehicle.driving
		player_hud.visible=not _vehicle_ui_active;player_hud.enabled=not _vehicle_ui_active
		var crosshair=help.get_parent().get_node_or_null("Crosshair")
		if crosshair!=null: crosshair.visible=not _vehicle_ui_active
		if _vehicle_ui_active:
			_walking_help=help.text
			help.text="W / S  Accelerate / Brake or reverse    A / D  Steer    Space  Handbrake    Shift  Boost\nE  Exit when stopped    R  Reset vehicle    Esc  Release mouse\nF5 Save · reload on foot beside the parked vehicle. Cosmetic dents are not saved."
		else: help.text=_walking_help
	super._process(delta)
	road_palette.panel.visible=not world_vehicle.driving and not structure_mode and not model_tool.active and not loading_active and not shutdown_requested and not player_hud.inventory_open and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE
	road_preview.visible=not world_vehicle.driving and not structure_mode and not model_tool.active and not loading_active and not shutdown_requested and not player_hud.inventory_open
	water_camera.update()
	pickups.update_view(delta,player.global_position,not loading_active and not shutdown_requested)
	terrain._record_stage("controller process",(Time.get_ticks_usec()-frame_begin)/1000.0)
	_update_prefab_preview(delta)
	model_tool.update(delta,_model_edit_available())
	if structures.blocks != null:
		structures.blocks.set_focus(player.position)
		if terrain.world_ready and (not temporary_world or terrain.backend.readonly_snapshot) and not shutdown_requested:
			if structures.enable_region_paging(terrain.backend.snapshot_codec):
				structures.step_region_paging(player.global_position)
		structures.model("architecture/metal_beam/v1").set_collision_focus(player.position)
		structures.model("architecture/doorway/v1").set_collision_focus(player.position)
		structures.model("architecture/metal_beam/v1").set_render_focus(player.position)
		structures.model("architecture/doorway/v1").set_render_focus(player.position)
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
	var query:=PhysicsRayQueryParameters3D.create(camera.global_position,point,3,[player.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _place_inventory_model(history: RefCounted, collection: Node3D, transforms: PackedFloat32Array, protection: AABB, costs: PackedInt64Array) -> int:
	if not _model_edit_available():
		model_tool.placement_failure="World interaction unavailable"
		return 0
	var id: int=construction_inventory.place_model(history,collection,player_hud.inventory,transforms,protection,costs)
	model_tool.placement_failure=construction_inventory.reason
	player_hud.refresh()
	return id

func _model_edit_available() -> bool:
	return not world_vehicle.driving and not loading_active and not shutdown_requested and not benchmark_enabled and not player_hud.inventory_open and app_focused and terrain.world_ready and not terrain.pending_edit

func _drop_inventory_supply(slot: int, revision: int) -> void:
	var result := {"ok":false,"reason":"Stand on foot in a ready world to drop supplies"}
	if player_hud.inventory_open and app_focused and not fly and not loading_active and not shutdown_requested and terrain.world_ready and not terrain.pending_edit and not world_vehicle.driving:
		var forward := -player.global_basis.z
		forward.y=0;forward=forward.normalized()
		var start := player.global_position+forward*1.2+Vector3.UP*1.5
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
				if clear: result=pickups.drop_one(player_hud.inventory,slot,revision,pickups.to_local(point))
	player_hud.message.text=result.reason
	player_hud.refresh()
