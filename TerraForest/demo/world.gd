extends "res://demo/controller.gd"
const Vegetation = preload("res://addons/vegetation/vegetation_world.gd")
const Ecosystem = preload("res://addons/world_ecosystem/world_ecosystem.gd")
const Lakes = preload("res://addons/volumetric_water/lake_world.gd")
const Persistence = preload("res://addons/world_runtime/world_persistence.gd")
const Structures = preload("res://addons/structures/structures_world.gd")
var persistence = Persistence.new()
var vegetation = Vegetation.new()
var ecosystem = Ecosystem.new()
var lakes = Lakes.new()
var structures = Structures.new()
var model_tool = preload("res://addons/structures/model_tool.gd").new()
var structure_mode := false
var structure_shape := 1
var structure_material := 0
var structure_rotation := 0
var structure_prefabs: Array[Resource] = []
var structure_prefab_index := -1
var prefab_preview := MeshInstance3D.new()
var _prefab_preview_material := StandardMaterial3D.new()
var _prefab_preview_timer := 0.0
var _prefab_preview_signature: Array = []
var _prefab_preview_clear := false
var telemetry := Label.new()
var _telemetry_time: float = 0.0
var _lake_notice: String = ""
var _lake_notice_until: int = 0

func _additional_motion_ready(delta: float) -> bool:
	if structures.blocks == null:
		return false
	# Cover capsule, floor snapping and any slide direction within this tick's
	# travel distance. The occupancy/readiness query itself is native.
	var bounds := AABB(player.global_position+Vector3(-0.34,-player.floor_snap_length,-0.34),Vector3(0.68,1.8+player.floor_snap_length,0.68))
	bounds = bounds.grow(player.velocity.length()*delta+0.05)
	return structures.is_collision_region_ready(bounds)

func _ready() -> void:
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
	if not structures_ready or not lakes.prepare() or not persistence.register_component("structures", structures.capture_storage_snapshot, structures.restore_storage_snapshot, structures.snapshot_validator(), structures.empty_snapshot()) or not persistence.register_component("volumetric_water", lakes.capture_snapshot, lakes.restore_snapshot, lakes.snapshot_validator(), lakes.empty_snapshot()) or not persistence.enable_region_structures(true) or persistence.attach(terrain) != OK:
		push_error("World persistence initialization failed")
		get_tree().quit(2)
		return
	_setup_prefabs()
	structures.blocks.configure_history(16*1024*1024,128)
	structures.blocks.configure_streaming(true,384,256,64*1024*1024,32*1024*1024)
	structures.model("architecture/metal_beam/v1").configure_collision(beam.get_aabb(),64,512,8)
	door_models.configure_compound_collision(doorway.get_meta("collision_boxes"),64,512,8,1536,24)
	terrain.nearby_first = true
	pending_spawn = Vector3(800, 0, 1310)
	terrain.focus = pending_spawn
	super._ready()
	add_child(model_tool)
	model_tool.configure(camera,player,[
		{"title":"Metal beam","mesh":beam,"collection":structures.model("architecture/metal_beam/v1"),"scale":Vector3(4,0.2,0.2)},
		{"title":"Floor panel","mesh":beam,"collection":structures.model("architecture/metal_beam/v1"),"scale":Vector3(4,0.25,4)},
		{"title":"Doorway","mesh":doorway,"collection":door_models,"scale":Vector3.ONE}],help.get_parent(),structures.blocks)
	model_tool.notice.connect(_show_lake_notice)
	DisplayServer.window_set_title("TerraForest | Living terrain")
	vegetation.name = "Vegetation"
	vegetation.camera = camera
	vegetation.sun_direction = sun.global_basis.z.normalized()
	add_child(vegetation)
	if vegetation.initialize() != OK:
		_message("Vegetation initialization failed; inspect the log")
		return
	ecosystem.name = "Ecosystem"
	ecosystem.terrain = terrain
	ecosystem.vegetation = vegetation
	ecosystem.camera = camera
	ecosystem.structures = structures
	add_child(ecosystem)
	lakes.name = "Lakes"
	lakes.terrain = terrain
	add_child(lakes)
	lakes.lake_ready.connect(func(_id: int): _show_lake_notice("Lake ready · temporary world" if temporary_world else "Lake ready · F5 saves world"))
	lakes.lake_failed.connect(func(_id: int, code: int): _show_lake_notice("Lake rejected (%d): open basin or blocked seed" % code))

func _show_lake_notice(text: String) -> void:
	_lake_notice = text
	_lake_notice_until = Time.get_ticks_msec()+6000
	_message(text)

func _setup_prefabs() -> void:
	for path in ["res://addons/structures/prefabs/brick_cottage.tres","res://addons/structures/prefabs/stair_flight.tres","res://addons/structures/prefabs/doorway_wall.tres","res://addons/structures/prefabs/tower_floor.tres"]:
		var asset: Resource = load(path)
		if asset != null and asset.get_cell_count()>0:
			structure_prefabs.append(asset)
			asset.changed.connect(_invalidate_prefab_preview)
	structures.blocks.changed.connect(_invalidate_prefab_preview)
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

func _prefab_allowed(asset: Resource, target: Vector3i) -> bool:
	var bounds: AABB = asset.placement_bounds(target,structure_rotation)
	return _prefab_player_clear(bounds) and structures.blocks.can_place_prefab(asset,target,structure_rotation)

func _prefab_player_clear(bounds: AABB) -> bool:
	var player_bounds := AABB(player.global_position+Vector3(-0.4,0,-0.4),Vector3(0.8,1.8,0.8))
	return not bounds.intersects(player_bounds)

func _invalidate_prefab_preview() -> void:
	_prefab_preview_signature.clear()
	_prefab_preview_timer=0.0

func _update_prefab_preview(delta: float) -> void:
	if not structure_mode or model_tool.active or structure_prefab_index<0 or loading_active or not app_focused:
		prefab_preview.hide()
		return
	_prefab_preview_timer -= delta
	if _prefab_preview_timer>0:
		return
	_prefab_preview_timer=0.1
	var hit := _structure_target(false)
	if hit.is_empty():
		prefab_preview.hide()
		return
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
	player.collision_mask |= 2
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
	help.text=help.text.replace("B  Terrain / Blocks", "B  Terrain / Blocks    M  Objects")
	help.offset_top = -88
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

func _unhandled_input(event: InputEvent) -> void:
	if not loading_active and not benchmark_enabled:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode==KEY_M:
				structure_mode=true
				model_tool.set_active(not model_tool.active)
				stroke_buffer.clear()
				held_previous=false
				stroke_valid=false
				last_capture_signature.clear()
				terrain.set_brush_active(false)
				_show_lake_notice("Object placement · 1–3 assets · R rotate" if model_tool.active else "Block construction")
				return
			if event.physical_keycode == KEY_B:
				model_tool.set_active(false)
				structure_mode = not structure_mode
				stroke_buffer.clear()
				held_previous = false
				stroke_valid = false
				last_capture_signature.clear()
				terrain.set_brush_active(false)
				_show_lake_notice("Block construction · 1–6 shapes · T material · R rotate" if structure_mode else "Terrain editing")
				return
		if model_tool.active and app_focused and terrain.world_ready:
			if model_tool.handle_input(event):
				return
		if event is InputEventKey and event.pressed and not event.echo:
			if structure_mode and not model_tool.active:
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
	if structure_mode:
		pointer.hide()
		if input_vector != Vector3.ZERO:
			terrain.note_interaction()
		terrain.set_brush_active(false)
		return
	super._update_edit(delta)

func _construction_history(forward: bool) -> void:
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
	return {"target":target}

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
		if structures.blocks.place_prefab(asset,target,structure_rotation):
			_show_lake_notice("%s placed · F5 saves world" % asset.resource_name)
		_prefab_preview_timer=0.0
		return
	if not remove and _brush_overlaps_player(Vector3(target)+Vector3.ONE*0.5,0.87):
		_show_lake_notice("Block placement intersects the player")
		return
	var word := 0 if remove else structure_shape+(structure_rotation<<3)+(structure_material<<5)
	if structures.blocks.set_cells(PackedInt32Array([target.x,target.y,target.z,word])):
		_show_lake_notice("Block removed · F5 saves world" if remove else "Block placed · F5 saves world")

func _process(delta: float) -> void:
	super._process(delta)
	_update_prefab_preview(delta)
	model_tool.update(delta,not loading_active and app_focused and terrain.world_ready)
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
		telemetry.text = "%d FPS  ·  %s trees  ·  %d cells\n%s" % [Engine.get_frames_per_second(), str(vegetation.renderer.roots.size()), ecosystem.resident.size(), activity]
