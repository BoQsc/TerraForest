# SPDX-License-Identifier: 0BSD
extends Node3D
const Recipe = preload("res://reviews/civic_buildings/recipes.gd")
const Trade = preload("res://addons/player_runtime/trader_inventory.gd")
const MODES := ["Exterior", "Rear", "Ground cutaway", "Inside", "Basement", "Upper floor"]
var structures: Node3D
var asset: Resource
var hinges: RefCounted
var camera: Camera3D
var ready_ok := false
var placement_results: Array[Dictionary] = []
var empty := PackedByteArray()
var original := PackedByteArray()
var selected := 0
var caption: Label
var orbit_target := Vector3.ZERO
var ground_root: Node3D
var actor: StaticBody3D
var trader = Trade.new()
var inventory: RefCounted = Trade.make_inventory()
var trading: CanvasLayer
var player: CharacterBody3D
var movement: RefCounted
var walking := false
var hud: PanelContainer
var save_status: Label
var archive: RefCounted
var save_path := ""

func _ready() -> void:
	DisplayServer.window_set_title("TerraForest | Trader and civic buildings / R1 review")
	structures = preload("res://addons/structures/structures_world.gd").new(); add_child(structures)
	if not structures.prepare(): return
	preload("res://addons/structures/furniture_catalog.gd").register(structures)
	preload("res://addons/structures/storage_catalog.gd").register(structures)
	preload("res://addons/structures/door_catalog.gd").register(structures)
	preload("res://addons/structures/window_catalog.gd").register(structures)
	empty = structures.capture_storage_snapshot()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR; environment.background_color = Color("bdcfd8")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.ambient_light_color = Color("d8e3ed")
	environment.ambient_light_energy = .7; environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC; environment.ssao_enabled = true
	var sky := WorldEnvironment.new(); sky.environment = environment; add_child(sky)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-44, -30, 0); sun.light_energy = 1.8
	sun.shadow_enabled = true; sun.directional_shadow_max_distance = 120; add_child(sun)
	camera = Camera3D.new(); camera.near = .04; camera.far = 300; camera.current = true; add_child(camera)
	player = CharacterBody3D.new(); player.collision_mask = 15; player.collision_layer = 2
	player.floor_snap_length = .35; player.floor_max_angle = deg_to_rad(48); player.floor_constant_speed = true; player.safe_margin = .004
	var capsule := CapsuleShape3D.new(); capsule.radius = .34; capsule.height = 1.8
	var shape := CollisionShape3D.new(); shape.shape = capsule; shape.position.y = .9; player.add_child(shape); add_child(player)
	movement = ClassDB.instantiate("NativePlayerMovement")
	inventory.grant_items(PackedInt64Array([Trade.CURRENCY, 300, 201, 25, 210, 20]), inventory.snapshot().revision)
	trading = preload("res://addons/player_runtime/trader_panel.gd").new(); add_child(trading)
	trading.closed.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if walking else Input.MOUSE_MODE_VISIBLE)
	trading.traded.connect(func(): save_status.text = "Trade changed / F5 saves this review session")
	interface()
	select_building(0)
	# Review economics is deliberately stored separately from every gameplay save.
	if "--persistent-review" in OS.get_cmdline_user_args():
		save_path = ProjectSettings.globalize_path("user://civic_trader_review_v1.tfworld")
		archive = ClassDB.instantiate("NativeWorldArchive")
		if not archive.acquire(save_path): save_path = ""; save_status.text = "Review save is in use; this session is temporary."
		elif FileAccess.file_exists(save_path): restore_trade()

func interface() -> void:
	var canvas := CanvasLayer.new(); add_child(canvas)
	hud = PanelContainer.new(); hud.position = Vector2(24, 22); canvas.add_child(hud)
	var style := StyleBoxFlat.new(); style.bg_color = Color(.035, .055, .065, .94)
	for side in ["left", "right", "top", "bottom"]: style.set("content_margin_" + side, 12)
	hud.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new(); hud.add_child(column)
	caption = Label.new(); caption.add_theme_font_size_override("font_size", 22); column.add_child(caption)
	var buildings := HBoxContainer.new(); column.add_child(buildings)
	for index in Recipe.IDS.size():
		var button := Button.new(); button.text = Recipe.TITLES[index]; button.pressed.connect(select_building.bind(index)); buildings.add_child(button)
	var views := HBoxContainer.new(); column.add_child(views)
	for index in MODES.size():
		var button := Button.new(); button.text = MODES[index]; button.pressed.connect(select_view.bind(index)); views.add_child(button)
	for entry in [["Walk / Esc menu", start_walk], ["Doors", toggle_doors], ["Save trade / F5", save_trade], ["Close", get_tree().quit]]:
		var button := Button.new(); button.text = entry[0]; button.pressed.connect(entry[1]); views.add_child(button)
	var help := Label.new(); help.text = "R1 designs awaiting review | right-drag orbit / wheel zoom | walking: WASD, Shift, E door or trader\nEach building part is destructible. Review sessions use a separate inventory and save."
	column.add_child(help)
	save_status = Label.new(); save_status.text = "Temporary review / stock and coins persist only with --persistent-review"; column.add_child(save_status)

func select_building(index: int) -> void:
	stop_walk(); trading.close(); selected = index; ready_ok = false
	if is_instance_valid(actor): actor.free(); actor = null
	if is_instance_valid(ground_root): ground_root.free()
	structures.restore_storage_snapshot(empty)
	asset = load("res://reviews/civic_buildings/baked/" + Recipe.IDS[index] + ".tres")
	if asset == null: return
	var transaction: RefCounted = ClassDB.instantiate("NativePrefabPlacement")
	var placed: Dictionary = transaction.place(structures.blocks, asset, Vector3i.ZERO, 0, structures.model_collections(), [])
	placement_results.append(placed)
	if not placed.get("ok", false): return
	var center: Vector3 = asset.get_bounds().get_center()
	structures.blocks.set_focus(center); structures.blocks.set_collision_radius(100); structures.blocks.flush_bakes(); structures.set_model_focus(center)
	original = structures.capture_storage_snapshot()
	ground_root = Node3D.new(); add_child(ground_root)
	var r: Rect2i = Recipe.BASEMENTS[index]
	if r.size == Vector2i.ZERO: ground(Rect2(-60, -60, 160, 160))
	else:
		ground(Rect2(-60, -60, r.position.x + 60, 160))
		ground(Rect2(r.end.x, -60, 100 - r.end.x, 160))
		ground(Rect2(r.position.x, -60, r.size.x, r.position.y + 60))
		ground(Rect2(r.position.x, r.end.y, r.size.x, 100 - r.end.y))
	if index == 0:
		actor = StaticBody3D.new(); actor.name = "Trader_civic_01"; actor.collision_layer = 8; actor.collision_mask = 0
		var capsule := CapsuleShape3D.new(); capsule.radius = .34; capsule.height = 1.8
		var collider := CollisionShape3D.new(); collider.shape = capsule; collider.position.y = .9; actor.add_child(collider)
		add_child(actor); actor.transform = asset.get_meta("trader_anchor")
		var human := preload("res://addons/characters/runtime/human_view.gd").new(); actor.add_child(human)
		human.position = Vector3.ZERO; human.rotation = Vector3.ZERO; human.set_third_person(true)
		human.set_process(false)
		human.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		human.animation_player.play(human.clips.get("Idle", human.clips["FP_Unarmed_Idle"]))
		# Same retained full player model, unarmed idle, with a single fixed body.
	ready_ok = true; select_view(0)

func ground(rect: Rect2) -> void:
	var body := StaticBody3D.new(); body.position = Vector3(rect.get_center().x, .85, rect.get_center().y)
	var box := BoxShape3D.new(); box.size = Vector3(rect.size.x, .2, rect.size.y)
	var collider := CollisionShape3D.new(); collider.shape = box; body.add_child(collider); ground_root.add_child(body)
	var mesh := MeshInstance3D.new(); var plane := PlaneMesh.new(); plane.size = rect.size
	var material := StandardMaterial3D.new(); material.albedo_color = Color("798273"); material.roughness = 1
	plane.material = material; mesh.mesh = plane; mesh.position.y = .1; body.add_child(mesh)

func select_view(index: int) -> void:
	if not ready_ok: return
	stop_walk(); trading.close(); structures.restore_storage_snapshot(original); hinges = ClassDB.instantiate("NativeHingedDoors")
	var bounds: AABB = asset.get_bounds(); var center: Vector3 = bounds.get_center(); var extent := maxf(bounds.size.x, bounds.size.z)
	if index in [2, 4, 5]:
		var ceiling := -1 if index == 4 else 8 if index == 5 else 4
		var removed := PackedInt32Array(); var records: PackedInt32Array = asset.get_records()
		for offset in range(0, records.size(), 4):
			if records[offset + 1] >= ceiling: removed.append_array(PackedInt32Array([records[offset], records[offset + 1], records[offset + 2], 0]))
		structures.blocks.set_cells(removed)
		for collection: Node3D in structures.model_collections().values():
			var hidden := PackedInt64Array()
			for id in collection.get_ids():
				var pose: PackedFloat32Array = collection.get_instance(id)
				if pose[7] >= ceiling: hidden.append(id)
			collection.remove_instances(hidden)
	structures.blocks.flush_bakes()
	ground_root.visible = index != 4
	if is_instance_valid(actor): actor.visible = index != 4
	camera.fov = 49 if index != 3 else 78
	orbit_target = Vector3(center.x, maxf(3, bounds.end.y * .35), center.z)
	match index:
		0: camera.position = orbit_target + Vector3(extent * 1.05, extent * .58, extent * 1.3)
		1: camera.position = orbit_target + Vector3(-extent, extent * .65, -extent * 1.2)
		2, 5:
			orbit_target.y = 2 if index == 2 else 6
			camera.position = orbit_target + Vector3(extent * .4, extent * 1.35, extent * .65)
		3: camera.position = Recipe.INSIDE[selected]; orbit_target = camera.position + Vector3(0, -.1, -8)
		4:
			var r: Rect2i = Recipe.BASEMENTS[selected]
			orbit_target = Vector3(r.get_center().x, -2, r.get_center().y); camera.position = orbit_target + Vector3(12, 17, 16)
	camera.look_at(orbit_target)
	caption.text = Recipe.TITLES[selected] + " / " + MODES[index] + " / R1\n" + Recipe.DESCRIPTIONS[selected]

func toggle_doors() -> void:
	if not ready_ok: return
	var collection: Node3D = structures.model("architecture/wooden_door/v1")
	for id in collection.get_ids(): hinges.toggle(collection, id, AABB())

func start_walk() -> void:
	if not ready_ok: return
	select_view(0)
	var route: Dictionary = asset.get_meta("stair_routes").filter(func(row): return row.kind in ["arrival", "loading bay"])[0]
	player.position = route.start; player.velocity = Vector3.ZERO; player.rotation = Vector3.ZERO
	camera.rotation = Vector3.ZERO; walking = true; hud.hide(); Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func stop_walk() -> void:
	walking = false
	if is_instance_valid(player): player.velocity = Vector3.ZERO
	if is_instance_valid(hud): hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func can_trade() -> bool:
	if selected != 0 or not walking or not is_instance_valid(actor): return false
	var start := camera.global_position; var target := actor.global_position + Vector3.UP * 1.45
	if start.distance_to(target) > 3: return false
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, target, 15, [player.get_rid()]))
	return not hit.is_empty() and hit.collider == actor

func interact() -> void:
	if can_trade():
		if trading.open_for(trader, inventory, can_trade): Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	var start := camera.global_position
	var hit: Dictionary = structures.blocks.raycast_scene(start, start - camera.global_basis.z * 3, 7, [player.get_rid()], true)
	var collection: Node3D = structures.model("architecture/wooden_door/v1")
	if not hit.is_empty() and hit.collider == collection: hinges.toggle(collection, collection.placement_for_body(hit.rid), AABB())

func save_trade() -> void:
	if save_path.is_empty(): save_status.text = "Temporary session: launch with --persistent-review to save."; return
	var bytes: PackedByteArray = archive.encode({"terrain":PackedByteArray(), "player_loadout":inventory.capture_storage_snapshot(), "trader_civic_01":trader.stock.capture_storage_snapshot()})
	save_status.text = "Review inventory and trader saved." if archive.publish(save_path, bytes) == OK else "SAVE FAILED: review state remains in memory."

func restore_trade() -> bool:
	var data: Dictionary = archive.decode(archive.read(save_path))
	if not data.get("ok", false): save_status.text = "Review save is invalid; saving disabled to retain it."; save_path = ""; return false
	var sections: Dictionary = data.sections
	if not sections.has("player_loadout") or not sections.has("trader_civic_01") or not inventory.validate_snapshot(sections.player_loadout) or not trader.stock.validate_snapshot(sections.trader_civic_01):
		save_status.text = "Review inventory is invalid; saving disabled to retain it."; save_path = ""; return false
	inventory.restore_storage_snapshot(sections.player_loadout); trader.stock.restore_storage_snapshot(sections.trader_civic_01)
	save_status.text = "Restored review inventory and finite trader stock."; return true

func _physics_process(delta: float) -> void:
	if not walking or trading.opened or not DisplayServer.window_is_focused(): return
	var direction := Vector3(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), 0, float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	direction = (player.basis * direction).normalized()
	player.velocity = movement.walking_velocity(direction, player.velocity, delta, Input.is_physical_key_pressed(KEY_SHIFT), player.is_on_floor(), Input.is_physical_key_pressed(KEY_SPACE))
	movement.move_grounded(player, delta)
	camera.position = player.position + Vector3.UP * 1.65

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE: stop_walk()
		elif event.physical_keycode == KEY_F5: save_trade()
		elif event.physical_keycode == KEY_E and walking: interact()
	elif event is InputEventMouseMotion:
		if walking and not trading.opened and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			player.rotation.y -= event.relative.x * .003; camera.rotation.y = player.rotation.y
			camera.rotation.x = clampf(camera.rotation.x - event.relative.y * .003, -1.45, 1.45)
		elif not walking and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			var offset := (camera.position - orbit_target).rotated(Vector3.UP, -event.relative.x * .006)
			var proposed := offset.rotated(camera.global_basis.x, -event.relative.y * .004)
			if absf(proposed.normalized().y) < .95: offset = proposed
			camera.position = orbit_target + offset; camera.look_at(orbit_target)
	elif not walking and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var offset := camera.position - orbit_target
		camera.position = orbit_target + offset.normalized() * clampf(offset.length() * (.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.1), .6, 160)

func _exit_tree() -> void:
	if archive != null: archive.release()
