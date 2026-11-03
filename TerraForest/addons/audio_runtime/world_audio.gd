# SPDX-License-Identifier: 0BSD
extends Node3D
## Single-player presentation adapter. Timer work is independent of world size.
const Runtime = preload("res://addons/audio_runtime/audio_runtime.gd")
var game: Node
var audio: Node3D
var timer: Timer
var initialized := false
var epoch := -1
var last_position := Vector3.ZERO
var distance := 0.0
var ticks := 0
var bed := 0
var bed_gain := -60.0
var fire_handles: Dictionary = {}
var fire_collections: Array[Node3D] = []
var surfaces: Dictionary = {}
var settings := ConfigFile.new()
var persist_settings := false
var sample_token := 810000000
var pending: Dictionary = {}
var last_surface := ""

func attach(host: Node) -> void:
	game = host; name = "WorldAudio"
	timer = Timer.new(); timer.wait_time = .05; timer.timeout.connect(tick); add_child(timer); timer.start()

func initialize() -> void:
	initialized = true
	audio = Runtime.new(); audio.name = "Playback"; add_child(audio)
	if not audio.prepare(Runtime.Catalog.enabled_paths()):
		# Reject the external set atomically, then retain the bundled default.
		push_warning("Audio packs rejected: " + str(audio.catalog.diagnostics))
		var builtin := "res://addons/audio_runtime/packs/nox/pack.audio.module.json"
		audio.prepare(PackedStringArray([builtin]) if FileAccess.file_exists(builtin) else PackedStringArray())
	persist_settings = not game.temporary_world and not ProjectSettings.get_setting("terraforest/offscreen_session", false)
	if persist_settings: settings.load("user://audio_preferences.cfg")
	audio.set_enabled(bool(settings.get_value("audio", "enabled", true)))
	for bus: String in Runtime.BUSES: audio.set_volume(bus, float(settings.get_value("audio", bus, .8)))
	for key: String in game.structures._models:
		var collection: Node3D = game.structures._models[key]
		var material: String = game.structures.object_definitions.get(key, {}).get("durability", {}).get("material", "")
		surfaces[collection.get_instance_id()] = "metal" if "metal" in key or "iron" in key else ("wood" if material == "wood" or "wood" in key or "floor" in key else "rock")
		if ("fireplace" in key or "standing_torch" in key or "campfire" in key) and fire_collections.size() < 8: fire_collections.append(collection)
	game.terrain.density_ray_received.connect(receive_surface)
	add_controls()
	reset_world()

func add_controls() -> void:
	var menu: CanvasLayer = game.session_menu
	if not menu.built: return
	menu.navigation["Audio"] = menu.button(menu.navigation["Graphics"].get_parent(), "Audio", menu.show_page.bind("Audio"))
	menu.navigation["Graphics"].get_parent().move_child(menu.navigation["Audio"], menu.navigation["Graphics"].get_index() + 1)
	var page: VBoxContainer = menu.page("Audio")
	menu.label(page, "Audio").add_theme_font_size_override("font_size", 22)
	var toggle := CheckButton.new(); toggle.text = "Environment and footsteps"; toggle.button_pressed = audio.enabled
	toggle.toggled.connect(func(value: bool): audio.set_enabled(value); preference("enabled", value)); page.add_child(toggle)
	for bus: String in Runtime.BUSES:
		menu.label(page, bus)
		var slider := HSlider.new(); slider.min_value = 0; slider.max_value = 1; slider.step = .01
		slider.value = clampf(float(settings.get_value("audio", bus, .8)), 0, 1); slider.custom_minimum_size.x = 320
		slider.value_changed.connect(func(value: float): audio.set_volume(bus, value); preference(bus, value)); page.add_child(slider)

func preference(key: String, value: Variant) -> void:
	settings.set_value("audio", key, value)
	if persist_settings: settings.save("user://audio_preferences.cfg")

func reset_world() -> void:
	audio.clear(); bed = 0; bed_gain = -60; fire_handles.clear(); pending.clear(); distance = 0
	epoch = game.terrain.epoch; last_position = game.player.global_position

func active() -> bool:
	return game.terrain.world_ready and not game.loading_active and not game.shutdown_requested and game.app_focused and not game.benchmark_enabled and not game.session_menu.pauses_world() and not game.player_view.entry.active and not game.player_life.dead

func tick() -> void:
	if not is_instance_valid(game): return
	if not initialized:
		if game.get("startup_complete") == true and game.session_menu.built: initialize()
		return
	if epoch != game.terrain.epoch: reset_world()
	audio.listener = game.camera.global_position
	if not active() or not audio.enabled:
		reset_world(); return
	ticks += 1
	if not pending.is_empty() and Time.get_ticks_msec() - pending.started > 100: finish_step(pending.surface)
	var position: Vector3 = game.player.global_position
	var travelled := Vector2(position.x - last_position.x, position.z - last_position.z).length()
	last_position = position
	if game.fly or game.world_vehicle.driving or not game.player.is_on_floor() or travelled > 2 or travelled < .001:
		distance = 0
	else:
		distance += travelled
		var gait := "run" if Vector2(game.player.velocity.x, game.player.velocity.z).length() > 7 else "walk"
		var stride := 2.7 if gait == "run" else 1.8
		if distance >= stride:
			distance = fmod(distance, stride)
			footstep(position, gait)
	if ticks % 5 == 0: soundscape()

func footstep(position: Vector3, gait: String) -> void:
	if not pending.is_empty(): finish_step(pending.surface)
	var hit: Dictionary = game.structures.blocks.raycast_scene(position + Vector3.UP * .35, position - Vector3.UP * .65, 7, [game.player.get_rid()])
	if hit.is_empty(): return
	var surface := "grass" if hit.get("normal", Vector3.UP).y > .8 else "rock"
	var collider: Object = hit.get("collider")
	if collider != null and collider.has_meta("audio_surface"): surface = str(collider.get_meta("audio_surface"))
	elif collider == game.structures.blocks and hit.has("cell"):
		surface = ["rock", "wood", "rock", "metal"][clampi(int(game.structures.blocks.decode_block(game.structures.blocks.get_cell(hit.cell)).material), 0, 3)]
	elif collider != null and surfaces.has(collider.get_instance_id()): surface = surfaces[collider.get_instance_id()]
	var point: Vector3 = hit.position
	if game._player_water_depth() > .05: return
	if game.lakes.depth_at(point + Vector3.UP * .05) > .03: surface = "water"
	pending = {"position": point, "gait": gait, "surface": surface, "started": Time.get_ticks_msec()}
	# Native worker supplies painted terrain material; at most one pending request.
	if surface in ["grass", "rock"] and (collider == null or not surfaces.has(collider.get_instance_id())) and collider != game.structures.blocks:
		sample_token += 1
		if game.terrain.request_density_ray(point + Vector3.UP * .3, point - Vector3.UP * .5, sample_token, 32, true): return
	finish_step(surface)

func receive_surface(reply: Dictionary) -> void:
	if pending.is_empty() or game.terrain.epoch != epoch or reply.get("token") != sample_token or reply.get("epoch") != epoch or reply.get("revision") != game.terrain.native_revision: return
	if reply.get("status") != "hit" or not reply.has("surface_material") or reply.position.distance_squared_to(pending.position) > .5: return
	var material := int(reply.surface_material)
	var surface: String = {1: "rock", 2: "wood", 3: "metal", 4: "rock", 8: "metal", 9: "metal", 10: "dirt"}.get(material, pending.surface)
	if material == 0 and (reply.get("surface_depth", 0) > 1.5 or reply.normal.y < .65): surface = "rock"
	if material == 0 and pending.position.y > 175 and reply.normal.y > .8: surface = "snow"
	finish_step(surface)

func finish_step(surface: String) -> void:
	if pending.is_empty(): return
	last_surface = surface
	audio.emit_event("movement.footstep", {"position": pending.position, "surface": surface, "gait": pending.gait})
	pending.clear()

func soundscape() -> void:
	var point: Vector3 = game.player.global_position
	# Reuse the existing forest cell index: one O(1) occupancy lookup, no tree scan.
	var renderer: Node3D = game.vegetation.renderer
	var cell := Vector2i(floori(point.x / renderer.CELL), floori(point.z / renderer.CELL))
	var occupied: bool = renderer.cells.has(cell) and not renderer.cells[cell].rows.is_empty()
	var roof: Dictionary = game.structures.blocks.raycast_scene(point + Vector3.UP * 1.8, point + Vector3.UP * 14, 7, [game.player.get_rid()])
	var target := 0.0 if occupied and roof.is_empty() else -60.0
	bed_gain = move_toward(bed_gain, target, 5.0)
	if bed == 0 and bed_gain > -60: bed = audio.start_loop("ambience.forest", {}, true)
	if bed > 0 and not audio.update_loop(bed, point, bed_gain): bed = 0
	if bed_gain <= -60 and bed > 0: audio.stop(bed); bed = 0
	var wanted := {}
	# Only collision-resident fires, already selected by native world streaming.
	# Fixed maxima: eight collections, 128 total candidates, eight audible fires.
	var visited := 0
	for collection in fire_collections:
		if visited >= 128: break
		if not is_instance_valid(collection): continue
		var ids: PackedInt64Array = collection.collision_identities()
		for i in mini(ids.size(), 128):
			if visited >= 128: break
			visited += 1
			var transform: PackedFloat32Array = collection.get_instance(ids[i])
			if transform.size() != 12: continue
			var source: Vector3 = collection.to_global(Vector3(transform[9], transform[10], transform[11]) + Vector3.UP * .6)
			if source.distance_squared_to(audio.listener) > 16 * 16 or wanted.size() >= 8: continue
			wanted[str(collection.get_instance_id()) + ":" + str(ids[i])] = source
	var torch: Node3D = game.tool_view.human.torch_effects
	if is_instance_valid(torch) and torch.burning and torch.is_visible_in_tree(): wanted["held-torch"] = torch.global_position
	for key: String in fire_handles.keys():
		if not wanted.has(key): audio.stop(fire_handles[key]); fire_handles.erase(key)
	for key: String in wanted:
		if fire_handles.has(key) and not audio.update_loop(fire_handles[key], wanted[key]): fire_handles.erase(key)
		if not fire_handles.has(key):
			var handle: int = audio.start_loop("fire.burn", {"position": wanted[key]})
			if handle > 0: fire_handles[key] = handle
