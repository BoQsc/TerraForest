extends Node3D
## Original Godot-only demo code, CC0-1.0. No plugins or external runtime libraries.
## Zombie limb health, animation and physics live in scripts/zombie.gd.

const PART_NAMES = {
	"torso": "TORSO", "head": "HEAD", "upper_arm_l": "LEFT UPPER ARM",
	"forearm_l": "LEFT FOREARM", "hand_l": "LEFT HAND", "upper_arm_r": "RIGHT UPPER ARM",
	"forearm_r": "RIGHT FOREARM", "hand_r": "RIGHT HAND", "thigh_l": "LEFT THIGH",
	"shin_l": "LEFT SHIN", "foot_l": "LEFT FOOT", "thigh_r": "RIGHT THIGH",
	"shin_r": "RIGHT SHIN", "foot_r": "RIGHT FOOT"
}
const CLIPS = ["Zombie_Idle", "Zombie_Walk", "Zombie_Attack", "Zombie_Hit"]
const CLIP_LABELS = ["IDLE", "SHAMBLE", "ATTACK", "HIT"]
const REVISION_MANIFEST = "res://assets/zombie.revisions.json"
const DEFAULT_REVISION = "original"
const INSPECTION_FPS = 60.0
const START_POSITION = Vector3(0.0, 0.08, 3.05)
const ACCENT = Color(0.78, 0.56, 0.27)
const INK = Color(0.84, 0.85, 0.81)
const DIM = Color(0.47, 0.54, 0.53)

var subject
var player: CharacterBody3D
var eyes: Node3D
var camera: Camera3D
var inspect_camera: Camera3D
var ui: Control
var status_label: Label
var state_label: Label
var limb_label: Label
var health_label: Label
var mode_label: Label
var inspection_panel: PanelContainer
var frame_label: Label
var clip_label: Label
var collider_label: Label
var message_label: Label
var mouse_label: Label
var reticle: Control
var hp_bar: ProgressBar
var hit_indicator: Label
var shot_sound: AudioStreamPlayer
var aim_subject
var aim_part = ""
var aim_hit: Dictionary = {}
var subject_count = 0
var maximum_limb_health: Dictionary = {}
var player_health = 100.0
var inspecting = false
var behavior_on = false
var inspect_yaw = 0.0
var inspect_pitch = 0.10
var inspect_distance = 3.5
var pitch = -0.16
var shot_cooldown = 0.0
var hit_time = 0.0
var message_time = 0.0
var move_time = 0.0
var effects: Array = []
var capture_path = ""
var recording_review = false
var current_clip = "IDLE"
var initialized = false
var animation_paused = false
var inspection_frame = 0
var paused_clip_resource: Animation
var paused_clip_loop_mode = Animation.LOOP_NONE
var show_colliders = false
var collision_overlay: Node3D
var collision_meshes: Dictionary = {}
var preview_collider_material: StandardMaterial3D
var active_collider_material: StandardMaterial3D
var selected_revision = DEFAULT_REVISION
var revision_profiles: Dictionary = {}
var revision_build_label = "Zombie Lab — Revision Selector"
var revision_label: Label
var revision_file_label: Label
var revision_description_label: Label
var revision_buttons: Dictionary = {}
var revision_button_group: ButtonGroup
var action_picker: OptionButton
var action_names: Array[String] = []
var ui_action_buttons: Array[Button] = []
var demo_start_button: Button
var demo_run_button: Button
var demo_stop_button: Button
var demo_restart_button: Button
var demo_stage_label: Label
var demo_contact_label: Label
var demo_note_label: Label
var demonstration


func _ready() -> void:
	Engine.max_fps = 60
	_load_revision_profiles()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--revision="):
			var requested = arg.trim_prefix("--revision=").to_lower()
			if _revision_available(requested):
				selected_revision = requested
			elif requested == "r3":
				push_warning("F3 / R3 is deprecated and archived; opening Original / Main.")
			else:
				push_warning("Unknown revision '%s'; opening Original / Main." % requested)
		elif arg.begins_with("--capture="):
			capture_path = arg.trim_prefix("--capture=")
		elif arg == "--review":
			recording_review = true
	_setup_input()
	_build_world()
	_build_player()
	_build_ui()
	_build_collision_overlay()
	_build_audio()
	_spawn_subject()
	_build_demonstration()
	initialized = true
	if recording_review:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_set_inspecting(true)
		inspect_yaw = 0.10
		inspect_pitch = 0.08
		inspect_distance = 2.8
		_update_inspect_camera()
		call_deferred("_record_review")
	elif capture_path.is_empty():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		call_deferred("_capture_scene")
	_set_message("F1 and F2 preserve the originals. F4 develops R4. Esc unlocks the action picker and the R4 demonstration button.", 8.0)
	print("[ZombieLab] Ready: ", selected_revision, " | F1 Original/Main | F2 Original alternate | F4 R4/Active | F3 archived | R reset | 1–4 base animations | action picker | R4 demonstration | P pause | ,/. step | C colliders.")


func _load_revision_profiles() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(REVISION_MANIFEST))
	if not manifest is Dictionary:
		push_error("Revision manifest is missing or invalid: " + REVISION_MANIFEST)
		return
	revision_build_label = String(manifest.get("build_label", revision_build_label))
	for row in manifest.get("revisions", []):
		if row is Dictionary and row.has("id") and row.has("model_path"):
			revision_profiles[String(row.id)] = row
	if not revision_profiles.has(DEFAULT_REVISION):
		push_error("The revision manifest must include Original / Main.")


func get_selected_revision() -> String:
	return selected_revision


func _revision_available(id: String) -> bool:
	if id == "r3" or not revision_profiles.has(id):
		return false
	return bool(revision_profiles[id].get("selectable", true))


func select_revision(id: String) -> void:
	var requested = id.to_lower()
	if requested == "r3":
		_set_message("F3 / R3 is deprecated and kept in the archive. Use F1, F2 or F4.", 5.0)
		return
	if not _revision_available(requested):
		_set_message("Unknown revision: " + id)
		push_warning("Unknown zombie revision: " + id)
		return
	if requested == selected_revision and is_instance_valid(subject):
		_update_revision_ui()
		return
	if is_instance_valid(demonstration):
		demonstration.stop(true)
	var previous_revision = selected_revision
	var previous_clip = "Zombie_Idle"
	var previous_frame = inspection_frame
	var was_paused = animation_paused
	var previous_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.025, 0))
	if is_instance_valid(subject):
		# Compare in the same place and orientation, including after pursuit.
		previous_transform = subject.global_transform
		if subject.animation_player != null:
			var assigned = String(subject.animation_player.assigned_animation).get_file()
			if not assigned.is_empty():
				previous_clip = assigned
	selected_revision = requested
	# Load before removing the current subject; a bad path leaves it available.
	if not _spawn_subject():
		selected_revision = previous_revision
		_update_revision_ui()
		return
	behavior_on = false
	subject.set_behavior(false)
	subject.global_transform = previous_transform
	subject.velocity = Vector3.ZERO
	if not action_names.has(previous_clip):
		previous_clip = "Zombie_Idle"
	_select_animation(previous_clip, false)
	if was_paused:
		_seek_animation_frame(previous_frame)
	if inspecting:
		_update_inspect_camera()
	_update_revision_ui()
	var playback = "paused frame %03d" % inspection_frame if was_paused else "playing from frame 000"
	_set_message("%s · %s · %s. All limbs restored; pursuit is off." % [revision_profiles[selected_revision].label, previous_clip.trim_prefix("Zombie_").to_lower(), playback], 5.0)
	print("[ZombieLab] Revision selected: ", selected_revision, " | ", revision_profiles[selected_revision].model_path, " | ", playback)


func _reset_subject() -> void:
	if is_instance_valid(demonstration):
		demonstration.stop(true)
	behavior_on = false
	_spawn_subject()


func _setup_input() -> void:
	var keys = {"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A,
		"move_right": KEY_D, "sprint": KEY_SHIFT, "jump": KEY_SPACE}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event = InputEventKey.new()
			event.physical_keycode = keys[action]
			InputMap.action_add_event(action, event)


func _unhandled_input(event: InputEvent) -> void:
	if not initialized or not capture_path.is_empty() or recording_review:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_TAB:
				_set_inspecting(not inspecting)
			KEY_R:
				_reset_subject()
			KEY_F1:
				select_revision("original")
			KEY_F2:
				select_revision("r2")
			KEY_F3:
				_set_message("F3 / R3 is deprecated and preserved in the archive. F4 is the active development version.", 5.0)
			KEY_F4:
				select_revision("r4")
			KEY_E:
				if is_instance_valid(subject):
					if is_instance_valid(demonstration) and demonstration.active:
						demonstration.stop()
					subject.die(-_active_camera().global_basis.z * 2.4)
					_set_message("Ragdoll released. Press R for a fresh subject.")
			KEY_G:
				if is_instance_valid(demonstration) and demonstration.active:
					demonstration.stop()
				_restore_inspection_loop()
				animation_paused = false
				behavior_on = not behavior_on
				if is_instance_valid(subject):
					subject.set_behavior(behavior_on)
				_set_message("Behavior: " + ("pursue and attack" if behavior_on else "stationary inspection"))
			KEY_P:
				_set_animation_paused(not animation_paused)
			KEY_COMMA:
				_step_animation(-1)
			KEY_PERIOD:
				_step_animation(1)
			KEY_C:
				show_colliders = not show_colliders
				collision_overlay.visible = show_colliders
				_set_message("Collider overlay " + ("on · gold: dormant rig proxies; cyan: active physics shapes." if show_colliders else "off."))
			KEY_1, KEY_2, KEY_3, KEY_4:
				var index = int(event.physical_keycode - KEY_1)
				_select_clip(index)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if inspecting:
			inspect_yaw -= event.relative.x * 0.005
			inspect_pitch = clampf(inspect_pitch + event.relative.y * 0.0035, -1.40, 1.40)
		else:
			player.rotate_y(-event.relative.x * 0.0024)
			pitch = clampf(pitch - event.relative.y * 0.0024, -1.30, 1.30)
			eyes.rotation.x = pitch
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_fire(false)
			MOUSE_BUTTON_RIGHT:
				_fire(true)
			MOUSE_BUTTON_WHEEL_UP:
				if inspecting:
					inspect_distance = clampf(inspect_distance - 0.22, 1.45, 7.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				if inspecting:
					inspect_distance = clampf(inspect_distance + 0.22, 1.45, 7.0)


func _physics_process(delta: float) -> void:
	if not initialized:
		return
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	if not inspecting:
		var motion = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED or not capture_path.is_empty() or recording_review:
			motion = Vector2.ZERO
		var direction = player.basis * Vector3(motion.x, 0, motion.y)
		var speed = 4.5 if Input.is_action_pressed("sprint") else 2.7
		player.velocity.x = move_toward(player.velocity.x, direction.x * speed, delta * 14.0)
		player.velocity.z = move_toward(player.velocity.z, direction.z * speed, delta * 14.0)
		if not player.is_on_floor():
			player.velocity.y -= 17.0 * delta
		elif Input.is_action_just_pressed("jump") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			player.velocity.y = 5.1
		player.move_and_slide()
		if player.position.y < -4.0:
			player.position = START_POSITION
			player.velocity = Vector3.ZERO
		move_time += delta * Vector2(player.velocity.x, player.velocity.z).length()
		eyes.position.y = 1.58 + (sin(move_time * 7.0) * 0.012 if player.is_on_floor() else 0.0)
	if inspecting:
		_update_inspect_camera()
	_query_aim()
	_update_effects(delta)


func _process(delta: float) -> void:
	if not initialized:
		return
	hit_time = maxf(0.0, hit_time - delta)
	message_time = maxf(0.0, message_time - delta)
	_update_ui()


func _active_camera() -> Camera3D:
	return inspect_camera if inspecting else camera


func _query_aim() -> void:
	var cam = _active_camera()
	var start = cam.global_position
	var end = start - cam.global_basis.z * 40.0
	var query = PhysicsRayQueryParameters3D.create(start, end, 1 | 4 | 8)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.exclude = [player.get_rid()]
	aim_hit = get_world_3d().direct_space_state.intersect_ray(query)
	aim_subject = null
	aim_part = ""
	if not aim_hit.is_empty():
		var collider = aim_hit.collider
		if collider.has_meta("limb_key") and collider.has_meta("zombie"):
			aim_subject = collider.get_meta("zombie")
			aim_part = str(collider.get_meta("limb_key"))


func _fire(force_sever: bool) -> void:
	if shot_cooldown > 0.0:
		return
	shot_cooldown = 0.17 if not force_sever else 0.28
	_query_aim()
	var cam = _active_camera()
	var direction = -cam.global_basis.z
	shot_sound.pitch_scale = 0.84 if force_sever else 1.04
	shot_sound.play()
	if aim_hit.is_empty():
		return
	var point: Vector3 = aim_hit.position
	if is_instance_valid(aim_subject) and not aim_part.is_empty():
		# An impact resumes animation reactions; ragdoll still captures this exact pose.
		if aim_subject == subject:
			_restore_inspection_loop()
			if animation_paused and subject.alive and subject.animation_player != null:
				subject.animation_player.play()
			animation_paused = false
		var label = str(PART_NAMES.get(aim_part, aim_part))
		var hit_name = "Heavy impact · " if force_sever and aim_part == "torso" else ("Sever impact · " if force_sever else "Hit · ")
		_set_message(hit_name + label.to_lower(), 1.8)
		aim_subject.receive_hit(aim_part, 32.0, point, direction * (4.5 if force_sever else 2.7), force_sever)
		hit_time = 0.17
		_burst(point, aim_hit.normal, true, 9 if force_sever else 5)
	else:
		var collider = aim_hit.collider
		if collider is RigidBody3D:
			collider.apply_impulse(direction * 2.7, point - collider.global_position)
		elif collider is PhysicalBone3D:
			collider.apply_impulse(direction * 2.7, point - collider.global_position)
		_burst(point, aim_hit.normal, false, 4)


func _spawn_subject() -> bool:
	var profile: Dictionary = revision_profiles.get(selected_revision, {})
	if profile.is_empty():
		push_error("No profile for zombie revision: " + selected_revision)
		return false
	var template = load("res://scenes/Zombie.tscn") as PackedScene
	if template == null:
		push_error("Zombie scene is missing: res://scenes/Zombie.tscn")
		return false
	var selected_model = load(String(profile.model_path)) as PackedScene
	if selected_model == null:
		push_error("Zombie revision model is missing: " + String(profile.model_path))
		_set_message("Could not load " + String(profile.model_path).get_file() + "; the current subject remains available.", 5.0)
		return false
	_restore_inspection_loop()
	_clear_subject_debris()
	if is_instance_valid(subject):
		remove_child(subject)
		subject.queue_free()
	subject = template.instantiate()
	subject.name = "Zombie"
	subject.target = player
	# Apply the complete revision before _ready() builds its rig and physics.
	subject.model_scene = selected_model
	subject.model_path = String(profile.model_path)
	subject.revision_id = selected_revision
	subject.behavior_contract_path = String(profile.get("behavior_contract_path", ""))
	subject.attack_strike_seconds = float(profile.attack_strike_seconds)
	subject.walk_reference_speed = float(profile.walk_reference_speed_mps)
	subject.walk_speed = float(profile.walk_speed_mps)
	add_child(subject)
	subject.position = Vector3(0, 0.025, 0)
	subject.set_behavior(behavior_on)
	maximum_limb_health = subject.limb_health.duplicate()
	animation_paused = false
	inspection_frame = 0
	player_health = 100.0
	if subject.has_signal("limb_severed"):
		subject.limb_severed.connect(_on_limb_severed)
	if subject.has_signal("died"):
		subject.died.connect(_on_subject_died)
	if subject.has_signal("attack_landed"):
		subject.attack_landed.connect(_on_player_hit)
	subject_count += 1
	current_clip = "IDLE"
	aim_subject = null
	aim_part = ""
	aim_hit.clear()
	_refresh_action_picker()
	_update_revision_ui()
	_set_message("%s · fresh subject %02d · all limbs restored." % [profile.label, subject_count], 3.0)
	print("[ZombieLab] Subject spawned: ", subject_count, " | ", selected_revision, " | ", profile.model_path)
	return true


func _clear_subject_debris() -> void:
	# Detached chains are siblings of the subject; remove them before the new
	# character enters the physics world, including every articulated segment.
	if is_instance_valid(subject):
		for body in subject.detached_parts:
			if is_instance_valid(body):
				if body.get_parent() != null:
					body.get_parent().remove_child(body)
				body.queue_free()
		subject.detached_parts.clear()
	for entry in collision_meshes.values():
		if is_instance_valid(entry.node):
			if entry.node.get_parent() != null:
				entry.node.get_parent().remove_child(entry.node)
			entry.node.queue_free()
	collision_meshes.clear()
	for effect in effects:
		if is_instance_valid(effect.node):
			if effect.node.get_parent() != null:
				effect.node.get_parent().remove_child(effect.node)
			effect.node.queue_free()
	effects.clear()
	hit_time = 0.0
	shot_cooldown = 0.0


func _on_limb_severed(part: String) -> void:
	_set_message(str(PART_NAMES.get(part, part)).to_lower().capitalize() + " severed · detached piece remains physical.", 3.0)


func _on_subject_died() -> void:
	_restore_inspection_loop()
	animation_paused = false
	_set_message("Subject down · physical ragdoll active. R creates a fresh subject.", 4.0)


func _on_player_hit(damage: float) -> void:
	if is_instance_valid(demonstration) and demonstration.active:
		return
	if inspecting:
		return
	player_health = maxf(0.0, player_health - damage)
	_set_message("Subject attack · %d / 100 health" % roundi(player_health), 2.0)
	if player_health <= 0.0:
		player.position = START_POSITION
		player.velocity = Vector3.ZERO
		player_health = 100.0
		behavior_on = false
		subject.set_behavior(false)
		_set_message("You were caught. Returned to the observation point; G resumes behavior.", 4.0)


func _set_inspecting(enabled: bool) -> void:
	inspecting = enabled
	inspect_camera.current = enabled
	camera.current = not enabled
	if enabled:
		var focus = Vector3.ZERO if not is_instance_valid(subject) else subject.global_position
		var offset = camera.global_position - focus
		inspect_yaw = atan2(offset.x, offset.z)
		inspect_distance = clampf(Vector2(offset.x, offset.z).length(), 1.45, 7.0)
		inspect_pitch = 0.10
		_update_inspect_camera()
	_set_message("Orbit inspection · mouse turns the view, wheel zooms." if enabled else "First person · WASD to move.")


func _select_clip(index: int) -> void:
	if index < 0 or index >= CLIPS.size():
		return
	_select_animation(CLIPS[index])


func select_action(clip_name: String) -> void:
	_select_animation(clip_name)


func _select_animation(clip_name: String, announce: bool = true) -> void:
	if not is_instance_valid(subject) or not subject.alive:
		_set_message("Reset the subject with R to inspect an animation.")
		return
	if not action_names.has(clip_name):
		_set_message("This revision does not include " + clip_name.trim_prefix("Zombie_") + ".")
		return
	if is_instance_valid(demonstration) and demonstration.active:
		demonstration.stop()
	_restore_inspection_loop()
	behavior_on = false
	subject.set_behavior(false)
	subject.play_clip(clip_name)
	subject.velocity = Vector3.ZERO
	var animation: AnimationPlayer = subject.animation_player
	var actual_clip = String(animation.assigned_animation).get_file() if animation != null else clip_name
	current_clip = _action_label(actual_clip).to_upper()
	if is_instance_valid(action_picker):
		action_picker.select(action_names.find(actual_clip))
	if animation != null:
		animation.advance(0.0)
		if animation_paused:
			_seek_animation_frame(0)
	if announce:
		if actual_clip != clip_name:
			_set_message("Current limbs use " + current_clip.to_lower() + ". R restores all limbs for the full action set.")
		else:
			_set_message("Animation: " + current_clip.to_lower() + (" · paused at frame 000" if animation_paused else ""))


func _action_label(clip_name: String) -> String:
	match clip_name:
		"Zombie_Idle": return "Idle"
		"Zombie_Walk": return "Shamble"
		"Zombie_Attack": return "Original attack"
		"Zombie_Hit": return "Hit reaction"
		"Zombie_Attack_Bite": return "Bite"
		"Zombie_Attack_Left": return "Left hand attack"
		"Zombie_Attack_Right": return "Right hand attack"
		"Zombie_Attack_Both": return "Both hands attack"
		"Zombie_Crawl": return "Crawl"
		"Zombie_Crawl_Idle": return "Crawl idle"
		"Zombie_Crawl_Bite": return "Crawl bite"
		"Zombie_Crawl_Hit": return "Crawl hit reaction"
		"Zombie_To_Crawl": return "Drop to crawl"
		"Zombie_Jump": return "Short jump"
		"Zombie_Climb_Ladder": return "Ladder climb"
	return clip_name.trim_prefix("Zombie_").replace("_", " ").capitalize()


func _refresh_action_picker() -> void:
	if not is_instance_valid(action_picker):
		return
	action_picker.clear()
	action_names.clear()
	if not is_instance_valid(subject) or subject.animation_player == null:
		return
	var available: Array[String] = []
	for key in subject.animation_player.get_animation_list():
		var clip_name = String(key).get_file()
		if clip_name.begins_with("Zombie_"):
			available.append(clip_name)
	var preferred = ["Zombie_Idle", "Zombie_Walk", "Zombie_Attack", "Zombie_Hit", "Zombie_Attack_Bite", "Zombie_Attack_Left", "Zombie_Attack_Right", "Zombie_Attack_Both", "Zombie_Crawl", "Zombie_Crawl_Idle", "Zombie_Crawl_Bite", "Zombie_Crawl_Hit", "Zombie_To_Crawl", "Zombie_Jump", "Zombie_Climb_Ladder"]
	for clip_name in preferred:
		if available.has(clip_name):
			action_names.append(clip_name)
	for clip_name in available:
		if not action_names.has(clip_name):
			action_names.append(clip_name)
	for clip_name in action_names:
		action_picker.add_item(_action_label(clip_name))
		action_picker.set_item_metadata(action_picker.item_count - 1, clip_name)
		var popup = action_picker.get_popup()
		popup.set_item_tooltip(action_picker.item_count - 1, clip_name)
	action_picker.disabled = action_names.is_empty()


func _on_action_selected(index: int) -> void:
	if index >= 0 and index < action_names.size():
		_select_animation(action_names[index])


func _build_demonstration() -> void:
	demonstration = load("res://scripts/zombie_demo.gd").new()
	demonstration.lab = self
	add_child(demonstration)


func start_demo() -> bool:
	if not is_instance_valid(demonstration):
		return false
	return demonstration.start()


func stop_demo() -> void:
	if is_instance_valid(demonstration):
		demonstration.stop()
	animation_paused = false
	_set_message("Demonstration stopped. Orbit, action inspection and limb controls remain available.", 5.0)


func restart_demo() -> bool:
	return start_demo()


func get_demo_snapshot() -> Dictionary:
	return demonstration.get_snapshot() if is_instance_valid(demonstration) else {"active": false, "stage": "unavailable"}


func _set_animation_paused(paused: bool) -> void:
	if not is_instance_valid(subject) or not subject.alive or subject.animation_player == null:
		_set_message("P pauses animation. Reset the subject with R to inspect a clip.")
		return
	var animation: AnimationPlayer = subject.animation_player
	if paused:
		# Manual mode cancels locomotion and reactions without pausing the camera or physics.
		# Remember the live pose before stopping behavior, which may select idle.
		var clip = String(animation.assigned_animation)
		var frame = roundi(animation.current_animation_position * INSPECTION_FPS) if not String(animation.current_animation).is_empty() else 0
		if clip.is_empty():
			clip = CLIPS[0]
		if is_instance_valid(demonstration) and demonstration.active:
			demonstration.stop()
		behavior_on = false
		subject.set_behavior(false)
		subject.play_clip(clip.get_file())
		subject.velocity = Vector3.ZERO
		animation.advance(0.0)
		animation_paused = true
		current_clip = clip.get_file().trim_prefix("Zombie_").to_upper()
		_seek_animation_frame(frame)
		_set_message("Animation paused · comma / period steps one 60 Hz frame; orbit remains available.")
	else:
		animation_paused = false
		var clip = animation.get_animation(animation.assigned_animation)
		if clip != null and not String(animation.current_animation).is_empty() and animation.current_animation_position >= clip.length - 0.00001:
			animation.seek(0.0, true)
		_restore_inspection_loop()
		animation.play()
		_set_message("Animation resumed.")


func _seek_animation_frame(frame: int) -> void:
	if not is_instance_valid(subject) or subject.animation_player == null:
		return
	var animation: AnimationPlayer = subject.animation_player
	var clip = animation.get_animation(animation.assigned_animation)
	if clip == null:
		return
	# Keep endpoint poses exact for the whole paused interval. Restoring a loop
	# immediately after seek lets the next AnimationMixer update wrap frame N to 0.
	if paused_clip_resource != clip:
		_restore_inspection_loop()
		paused_clip_resource = clip
		paused_clip_loop_mode = clip.loop_mode
	clip.loop_mode = Animation.LOOP_NONE
	inspection_frame = clampi(frame, 0, roundi(clip.length * INSPECTION_FPS))
	animation.pause()
	animation.seek(minf(float(inspection_frame) / INSPECTION_FPS, clip.length), true)
	animation.pause()
	animation_paused = true


func _restore_inspection_loop() -> void:
	if paused_clip_resource != null:
		paused_clip_resource.loop_mode = paused_clip_loop_mode
	paused_clip_resource = null
	paused_clip_loop_mode = Animation.LOOP_NONE


func _step_animation(direction: int) -> void:
	if not is_instance_valid(subject) or not subject.alive:
		_set_message("Reset the subject with R to step through an animation.")
		return
	if not animation_paused:
		_set_animation_paused(true)
	_seek_animation_frame(inspection_frame + direction)


func _build_collision_overlay() -> void:
	collision_overlay = Node3D.new()
	collision_overlay.name = "ColliderInspection"
	add_child(collision_overlay)
	collision_overlay.hide()
	preview_collider_material = StandardMaterial3D.new()
	preview_collider_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	preview_collider_material.no_depth_test = true
	preview_collider_material.albedo_color = Color(1.0, 0.65, 0.23)
	active_collider_material = preview_collider_material.duplicate()
	active_collider_material.albedo_color = Color(0.15, 0.94, 0.84)
	# Evaluate after animation and physics updates, just before the current frame draws.
	RenderingServer.frame_pre_draw.connect(_update_collision_overlay)


func _update_collision_overlay() -> void:
	if not show_colliders or not is_instance_valid(subject):
		return
	var seen: Dictionary = {}
	for bone_name in subject.physical_bones:
		var body: PhysicalBone3D = subject.physical_bones[bone_name]
		if not is_instance_valid(body):
			continue
		for child in body.get_children():
			if not child is CollisionShape3D or child.shape == null:
				continue
			var shape_transform: Transform3D = child.global_transform
			if subject.alive:
				# Dormant PhysicalBone nodes do not track animation in every Godot backend.
				# Use the exact current rig pose and stored body/shape offsets for this preview.
				var index = subject.skeleton.find_bone(String(bone_name))
				shape_transform = subject.skeleton.global_transform * subject.skeleton.get_bone_global_pose(index) * body.body_offset * child.transform
			_overlay_shape(child, shape_transform, not subject.alive and body.collision_layer != 0, seen)
	for root_body in subject.detached_parts:
		if not is_instance_valid(root_body):
			continue
		var bodies: Array = root_body.get_meta("segment_bodies", [root_body])
		for body in bodies:
			if not is_instance_valid(body):
				continue
			for child in body.get_children():
				if child is CollisionShape3D and child.shape != null:
					_overlay_shape(child, child.global_transform, body.collision_layer != 0, seen)
	for key in collision_meshes.keys():
		if not seen.has(key):
			collision_meshes[key].node.queue_free()
			collision_meshes.erase(key)


func _overlay_shape(shape: CollisionShape3D, shape_transform: Transform3D, active: bool, seen: Dictionary) -> void:
	var key = shape.get_instance_id()
	seen[key] = true
	if not collision_meshes.has(key):
		var visual = MeshInstance3D.new()
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		collision_overlay.add_child(visual)
		collision_meshes[key] = {"node": visual, "shape": null}
	var entry: Dictionary = collision_meshes[key]
	if entry.shape != shape.shape:
		entry.shape = shape.shape
		entry.node.mesh = _collision_wire_mesh(shape.shape.get_debug_mesh())
	entry.node.material_override = active_collider_material if active else preview_collider_material
	entry.node.global_transform = shape_transform
	entry.node.visible = not shape.disabled


func _collision_wire_mesh(source: ArrayMesh) -> ArrayMesh:
	# Shape3D debug meshes may contain solid triangles. Draw their actual edges so
	# inspection never hides the skinned body behind an opaque proxy silhouette.
	var lines = PackedVector3Array()
	for surface in range(source.get_surface_count()):
		var arrays = source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices = arrays[Mesh.ARRAY_INDEX]
		if indices == null or indices.is_empty():
			indices = PackedInt32Array()
			for index in range(vertices.size()):
				indices.append(index)
		var primitive = source.surface_get_primitive_type(surface)
		if primitive == Mesh.PRIMITIVE_LINES:
			for index in indices:
				lines.append(vertices[index])
		elif primitive == Mesh.PRIMITIVE_TRIANGLES:
			var edges: Dictionary = {}
			for face in range(0, indices.size() - 2, 3):
				for edge in [[indices[face], indices[face + 1]], [indices[face + 1], indices[face + 2]], [indices[face + 2], indices[face]]]:
					var key = Vector2i(mini(edge[0], edge[1]), maxi(edge[0], edge[1]))
					if not edges.has(key):
						edges[key] = true
						lines.append(vertices[edge[0]])
						lines.append(vertices[edge[1]])
	var wire = ArrayMesh.new()
	if not lines.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = lines
		wire.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return wire


func _update_inspect_camera() -> void:
	var origin = Vector3.ZERO
	if is_instance_valid(subject):
		origin = subject.global_position
		if not subject.alive:
			var hips = subject.physical_bones.get("Hips")
			if is_instance_valid(hips):
				origin = hips.global_position
	var focus_height = 0.96 if (not is_instance_valid(subject) or subject.alive) else 0.10
	if is_instance_valid(subject) and subject.alive and subject.has_method("get_behavior_snapshot"):
		var snapshot: Dictionary = subject.get_behavior_snapshot()
		if String(snapshot.get("movement_mode", "standing")) in ["crawl", "crawling", "prone"]:
			focus_height = 0.42
		elif String(snapshot.get("movement_mode", "standing")) == "to_crawl":
			focus_height = lerpf(0.96, 0.42, smoothstep(0.0, 0.8, float(snapshot.get("action_time", 0.0))))
	var focus = origin + Vector3(0, focus_height, 0)
	if is_instance_valid(demonstration) and demonstration.active and demonstration.stage not in ["jump", "ladder"] and is_instance_valid(demonstration.target):
		# Frame the interaction while preserving the user's orbit angle and zoom.
		var target_offset: Vector3 = demonstration.target.global_position - origin
		target_offset.y = 0.0
		focus += (target_offset * 0.40).limit_length(1.10)
	var offset = Vector3(sin(inspect_yaw) * cos(inspect_pitch), sin(inspect_pitch), cos(inspect_yaw) * cos(inspect_pitch)) * inspect_distance
	inspect_camera.global_position = focus + offset
	inspect_camera.look_at(focus)


func _build_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.collision_layer = 2
	player.collision_mask = 1
	add_child(player)
	player.position = START_POSITION
	var shape = CapsuleShape3D.new()
	shape.radius = 0.24
	shape.height = 1.65
	var collision = CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = 0.825
	player.add_child(collision)
	eyes = Node3D.new()
	eyes.name = "Eyes"
	eyes.position.y = 1.58
	eyes.rotation.x = pitch
	player.add_child(eyes)
	camera = Camera3D.new()
	camera.name = "FirstPersonCamera"
	camera.fov = 58.0
	camera.near = 0.05
	camera.far = 85.0
	eyes.add_child(camera)
	camera.current = true
	inspect_camera = Camera3D.new()
	inspect_camera.name = "InspectionCamera"
	inspect_camera.fov = 53.0
	inspect_camera.near = 0.05
	inspect_camera.far = 85.0
	add_child(inspect_camera)


func _material(color: Color, roughness: float = 0.85, metallic: float = 0.0) -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat


func _box(label: String, at: Vector3, size: Vector3, material: Material, solid: bool = false) -> MeshInstance3D:
	var box = MeshInstance3D.new()
	box.name = label
	var mesh = BoxMesh.new()
	mesh.size = size
	box.mesh = mesh
	box.material_override = material
	box.position = at
	add_child(box)
	if solid:
		var body = StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape = CollisionShape3D.new()
		var bounds = BoxShape3D.new()
		bounds.size = size
		shape.shape = bounds
		body.add_child(shape)
		box.add_child(body)
	return box


func _cylinder(label: String, at: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var node = MeshInstance3D.new()
	node.name = label
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	node.mesh = mesh
	node.material_override = material
	node.position = at
	add_child(node)
	return node


func _world_label(text_value: String, at: Vector3, font_size: int, color: Color) -> Label3D:
	var label = Label3D.new()
	label.text = text_value
	label.position = at
	label.font_size = font_size
	label.pixel_size = 0.008
	label.modulate = color
	label.no_depth_test = false
	label.shaded = true
	label.outline_size = 0
	add_child(label)
	return label


func _concrete_grain() -> ImageTexture:
	# Original tileable mottling, generated with arithmetic and the built-in Image API.
	var texture = Image.create(128, 128, false, Image.FORMAT_RGB8)
	var generator = RandomNumberGenerator.new()
	generator.seed = 6041
	for y in range(128):
		for x in range(128):
			var u = float(x) / 128.0 * TAU
			var v = float(y) / 128.0 * TAU
			var blotch = sin(u * 2.0 + sin(v * 3.0)) * sin(v * 4.0 - u)
			var tone = 0.76 + blotch * 0.105 + generator.randf_range(-0.065, 0.065)
			texture.set_pixel(x, y, Color(tone, tone, tone))
	texture.generate_mipmaps()
	return ImageTexture.create_from_image(texture)


func _build_world() -> void:
	var concrete = _material(Color(0.24, 0.265, 0.255), 0.95)
	var wall = _material(Color(0.22, 0.245, 0.24), 0.94)
	var grain = _concrete_grain()
	concrete.albedo_texture = grain
	concrete.uv1_scale = Vector3(12, 12, 1)
	wall.albedo_texture = grain
	wall.uv1_scale = Vector3(9, 5, 1)
	var seam = _material(Color(0.065, 0.078, 0.075), 1.0)
	var steel = _material(Color(0.11, 0.14, 0.14), 0.63, 0.35)
	var rust = _material(Color(0.24, 0.13, 0.079), 0.9, 0.12)
	var paint = _material(Color(0.47, 0.32, 0.14), 0.83)
	var pale = _material(Color(0.59, 0.61, 0.55), 0.88)
	_box("Courtyard", Vector3(0, -0.16, 0), Vector3(18, 0.32, 20), concrete, true)
	_box("RearWall", Vector3(0, 2.1, -5.7), Vector3(18, 4.2, 0.32), wall, true)
	_box("LeftWall", Vector3(-7.1, 1.8, 0.9), Vector3(0.28, 3.6, 13.5), wall, true)
	_box("RightWall", Vector3(7.1, 1.8, 0.9), Vector3(0.28, 3.6, 13.5), wall, true)
	_box("FrontBarrier", Vector3(0, 0.5, 8.5), Vector3(14.5, 1, 0.4), wall, true)
	for x in [-6.8, -3.6, 3.6, 6.8]:
		_box("RearColumn", Vector3(x, 2.18, -5.38), Vector3(0.18, 4.36, 0.42), steel)
	for y in [0.30, 1.25, 2.2, 3.15, 4.12]:
		_box("RearMortar", Vector3(0, y, -5.53), Vector3(17.8, 0.022, 0.012), seam)
	_box("DoorFrame", Vector3(0, 1.47, -5.40), Vector3(2.15, 2.94, 0.22), steel)
	_box("ServiceDoor", Vector3(0, 1.42, -5.25), Vector3(1.86, 2.84, 0.10), _material(Color(0.18, 0.23, 0.21), 0.75, 0.2))
	_box("DoorSplit", Vector3(0, 1.40, -5.19), Vector3(0.018, 2.77, 0.01), seam)
	_box("DoorHandleL", Vector3(-0.13, 1.35, -5.11), Vector3(0.038, 0.26, 0.07), pale)
	_box("DoorHandleR", Vector3(0.13, 1.35, -5.11), Vector3(0.038, 0.26, 0.07), pale)
	_world_label("CONTAINMENT", Vector3(0, 3.43, -5.14), 42, Color(0.67, 0.67, 0.56))
	_world_label("B A Y   0 4", Vector3(0, 3.01, -5.12), 24, Color(0.48, 0.51, 0.46))
	_world_label("04", Vector3(-4.65, 2.35, -5.34), 132, Color(0.39, 0.42, 0.38))
	_world_label("AUTHORIZED\nPERSONNEL ONLY", Vector3(4.7, 1.72, -5.30), 21, Color(0.59, 0.56, 0.40))
	# Floor slabs, drain and restraint-area paint give visual depth without textures.
	for x in [-6.0, -3.0, 3.0, 6.0]:
		_box("SlabSeam", Vector3(x, 0.003, 0.8), Vector3(0.015, 0.006, 16.0), seam)
	for z in [-3.8, -1.0, 2.0, 5.2, 8.0]:
		_box("SlabSeam", Vector3(0, 0.004, z), Vector3(14.0, 0.006, 0.015), seam)
	_box("Drain", Vector3(-4.8, 0.008, -0.5), Vector3(0.36, 0.012, 7.3), steel)
	for n in range(35):
		_box("DrainSlit", Vector3(-4.8, 0.017, -4.0 + n * 0.21), Vector3(0.28, 0.01, 0.048), seam)
	for x in [-1.42, 1.42]:
		_box("BayPaint", Vector3(x, 0.008, 0.0), Vector3(0.052, 0.009, 2.6), paint)
	for z in [-1.3, 1.3]:
		_box("BayPaint", Vector3(0, 0.008, z), Vector3(2.9, 0.009, 0.052), paint)
	for n in range(7):
		var stripe = _box("CautionStripe", Vector3(-1.1 + n * 0.37, 0.013, -1.51), Vector3(0.12, 0.007, 0.32), paint)
		stripe.rotation.y = 0.45
	# Low crates and pipes leave the central subject unobstructed.
	for values in [[Vector3(-4.6, 0.45, -3.75), Vector3(1.35, 0.9, 0.95)],
		[Vector3(-3.95, 0.30, -3.0), Vector3(0.9, 0.6, 0.8)],
		[Vector3(5.0, 0.50, -3.55), Vector3(1.2, 1.0, 1.0)]]:
		var at: Vector3 = values[0]
		var size: Vector3 = values[1]
		_box("StorageCrate", at, size, steel, true)
		for offset in [-0.3, 0.3]:
			_box("CrateBand", at + Vector3(offset, 0, 0.015 + size.z * 0.5), Vector3(0.05, size.y, 0.025), rust)
	for x in [5.5, 5.78]:
		_cylinder("RiserPipe", Vector3(x, 2.1, -5.08), 0.065, 4.2, rust)
	_box("ElectricalCabinet", Vector3(-5.83, 1.52, -5.05), Vector3(0.63, 1.04, 0.32), steel)
	_box("CabinetLatch", Vector3(-5.61, 1.55, -4.87), Vector3(0.026, 0.15, 0.025), pale)
	# A cool overcast fill and warm work lamps maintain readable skin and clothing.
	var environment = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.11, 0.145, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.48, 0.57, 0.62)
	env.ambient_light_energy = 0.52
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.environment = env
	add_child(environment)
	var sun = DirectionalLight3D.new()
	sun.name = "OvercastSun"
	sun.rotation_degrees = Vector3(-54, -30, 0)
	sun.light_color = Color(0.80, 0.85, 0.84)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)
	var key = OmniLight3D.new()
	key.name = "SubjectKey"
	key.position = Vector3(-2.3, 3.2, 2.2)
	key.light_color = Color(1.0, 0.83, 0.64)
	key.light_energy = 1.6
	key.omni_range = 7.5
	key.shadow_enabled = false
	add_child(key)
	var fill = OmniLight3D.new()
	fill.name = "SubjectRim"
	fill.position = Vector3(2.3, 2.1, -2.0)
	fill.light_color = Color(0.55, 0.72, 0.83)
	fill.light_energy = 1.3
	fill.omni_range = 6.0
	add_child(fill)
	var lamp_mat = _material(Color(0.93, 0.71, 0.40))
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(0.90, 0.53, 0.18)
	lamp_mat.emission_energy_multiplier = 2.0
	for x in [-2.1, 2.1]:
		_box("WorkLampHousing", Vector3(x, 3.58, -5.04), Vector3(0.75, 0.12, 0.25), steel)
		_box("WorkLamp", Vector3(x, 3.52, -5.02), Vector3(0.61, 0.015, 0.15), lamp_mat)
		var light = OmniLight3D.new()
		light.position = Vector3(x, 3.35, -4.8)
		light.light_color = Color(1.0, 0.71, 0.36)
		light.light_energy = 1.45
		light.omni_range = 4.5
		add_child(light)


func _label(parent: Node, text_value: String, size: int, color: Color = INK) -> Label:
	var label = Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _panel(at: Vector2, size: Vector2) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.position = at
	panel.size = size
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.029, 0.042, 0.043, 0.92)
	style.border_color = Color(0.25, 0.31, 0.29, 0.65)
	style.set_border_width_all(1)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 13
	style.content_margin_bottom = 13
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)
	return panel


func _revision_button(parent: Node, id: String, title: String, prominent: bool) -> Button:
	var button = Button.new()
	button.name = "Revision_" + id
	button.text = title
	button.toggle_mode = true
	button.button_group = revision_button_group
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 45 if prominent else 30
	button.add_theme_font_size_override("font_size", 14 if prominent else 12)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.85, 0.58))
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.105, 0.10)
	normal.border_color = Color(0.27, 0.33, 0.30)
	normal.set_border_width_all(1)
	normal.content_margin_left = 10
	normal.content_margin_right = 10
	var hover = normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.16, 0.185, 0.155)
	hover.border_color = ACCENT
	var pressed = normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.23, 0.185, 0.11)
	pressed.border_color = ACCENT
	pressed.set_border_width_all(2)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	button.pressed.connect(select_revision.bind(id))
	parent.add_child(button)
	revision_buttons[id] = button
	return button


func _build_revision_ui() -> void:
	var panel = _panel(Vector2(30, 130), Vector2(410, 258))
	panel.name = "RevisionSelector"
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)
	_label(content, "ACTIVE REVISION", 12, ACCENT)
	revision_label = _label(content, "ORIGINAL / MAIN", 22, INK)
	revision_label.name = "ActiveRevision"
	revision_file_label = _label(content, "ASSET  Zombie.glb", 12, DIM)
	revision_file_label.name = "ActiveRevisionFile"
	revision_description_label = _label(content, "Startup default · first released zombie", 12, INK)
	revision_description_label.custom_minimum_size = Vector2(370, 31)
	revision_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	revision_button_group = ButtonGroup.new()
	var main_choices = HBoxContainer.new()
	main_choices.add_theme_constant_override("separation", 8)
	content.add_child(main_choices)
	_revision_button(main_choices, "original", "F1  Original / Main", true)
	_revision_button(main_choices, "r4", "F4  R4 / Active", true)
	var other_choices = HBoxContainer.new()
	other_choices.add_theme_constant_override("separation", 8)
	content.add_child(other_choices)
	_revision_button(other_choices, "r2", "F2  Original alternate", false)
	var archived = _label(other_choices, "F3 / R3 archived", 12, DIM)
	archived.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	archived.custom_minimum_size.x = 118
	_label(content, "Esc unlocks buttons · F1 / F2 / F4 select versions", 12, DIM)
	_label(content, "R resets this revision · startup always Original", 12, DIM)
	_update_revision_ui()


func _command_button(parent: Node, title: String, callback: Callable, primary: bool = false) -> Button:
	var button = Button.new()
	button.text = title
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 36 if primary else 28
	button.add_theme_font_size_override("font_size", 13 if primary else 12)
	button.add_theme_color_override("font_color", Color(1.0, 0.87, 0.63) if primary else INK)
	button.add_theme_color_override("font_disabled_color", DIM)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.23, 0.18, 0.10) if primary else Color(0.075, 0.105, 0.102)
	style.border_color = ACCENT if primary else Color(0.27, 0.33, 0.30)
	style.set_border_width_all(1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	button.add_theme_stylebox_override("normal", style)
	var hover = style.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.25, 0.26, 0.18)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	var disabled = style.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(0.07, 0.09, 0.085)
	disabled.border_color = Color(0.20, 0.25, 0.22)
	button.add_theme_stylebox_override("disabled", disabled)
	button.pressed.connect(callback)
	parent.add_child(button)
	ui_action_buttons.append(button)
	return button


func _build_demonstration_ui() -> void:
	var panel = _panel(Vector2(30, 410), Vector2(410, 253))
	panel.name = "DemonstrationControls"
	var stack = VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	panel.add_child(stack)
	_label(stack, "R4  /  LIVE DEMONSTRATION", 12, ACCENT)
	demo_start_button = _command_button(stack, "▶   Run R4 demonstration", start_demo, true)
	demo_start_button.name = "RunDemonstration"
	demo_run_button = demo_start_button
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	stack.add_child(row)
	demo_stop_button = _command_button(row, "Stop", stop_demo)
	demo_stop_button.name = "StopDemonstration"
	demo_restart_button = _command_button(row, "Restart cycle", restart_demo)
	demo_restart_button.name = "RestartDemonstration"
	var loop_label = _label(row, "LOOPS UNTIL STOPPED", 10, DIM)
	loop_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	demo_stage_label = _label(stack, "Pursuit · four attacks · hop · ladder\nOne leg / both legs lost → crawl", 13, INK)
	demo_stage_label.custom_minimum_size = Vector2(372, 38)
	demo_stage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	demo_contact_label = _label(stack, "LIVE TARGET   100 HP   ·   0 CONTACTS", 12, ACCENT)
	demo_note_label = _label(stack, "Run selects R4 and restores all limbs.\nF1 and F2 stay available as originals.", 12, DIM)
	demo_note_label.custom_minimum_size = Vector2(372, 35)
	demo_note_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _update_revision_ui() -> void:
	var profile: Dictionary = revision_profiles.get(selected_revision, {})
	if profile.is_empty():
		return
	if is_instance_valid(revision_label):
		revision_label.text = String(profile.label).to_upper()
		var clip_count = action_names.size() if is_instance_valid(subject) and subject.revision_id == selected_revision else 0
		revision_file_label.text = "ASSET  " + String(profile.model_path).get_file() + ("  ·  %d clips" % clip_count if clip_count > 0 else "")
		revision_file_label.tooltip_text = String(profile.model_path) + "\nSHA-256: " + String(profile.get("model_sha256", ""))
		revision_description_label.text = ("" if selected_revision == DEFAULT_REVISION else "Optional · ") + String(profile.get("description", ""))
	for id in revision_buttons:
		revision_buttons[id].set_pressed_no_signal(id == selected_revision)
	get_window().title = "%s | %s | %s" % [revision_build_label, profile.label, String(profile.model_path).get_file()]


func _build_ui() -> void:
	var canvas = CanvasLayer.new()
	canvas.name = "HUD"
	add_child(canvas)
	ui = Control.new()
	ui.name = "Interface"
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui)
	var top = VBoxContainer.new()
	top.position = Vector2(34, 28)
	top.add_theme_constant_override("separation", 2)
	ui.add_child(top)
	_label(top, "B G 5   /   C O N T A I N M E N T", 13, ACCENT)
	_label(top, "ZOMBIE LAB", 30)
	_label(top, "ORIGINALS  /  R4 ACTIONS  /  LIMBS & RAGDOLL", 12, DIM)
	_build_revision_ui()
	_build_demonstration_ui()
	var state_box = VBoxContainer.new()
	ui.add_child(state_box)
	state_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	state_box.offset_left = -330
	state_box.offset_right = -34
	state_box.offset_top = 30
	state_box.offset_bottom = 130
	state_label = _label(state_box, "SUBJECT 01   •   ACTIVE", 16, ACCENT)
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label = _label(state_box, "14 LIMBS INTACT", 13, DIM)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mode_label = _label(state_box, "STATIONARY  /  IDLE", 13, INK)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var controls = _panel(Vector2(30, -204), Vector2(410, 174))
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.offset_left = 30
	controls.offset_right = 440
	controls.offset_top = -204
	controls.offset_bottom = -30
	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	controls.add_child(content)
	_label(content, "TEST CONTROLS", 12, ACCENT)
	_label(content, "LMB  Damage         RMB  Sever         E  Ragdoll", 14)
	_label(content, "R  Reset this revision      G  Pursue / hold", 14)
	_label(content, "1  Idle    2  Shamble    3  Attack    4  Hit", 14)
	_label(content, "P  Pause   •   , / .  Frame step   •   C  Colliders", 12, DIM)
	_label(content, "WASD  Move   •   Shift  Run   •   Space  Jump", 12, DIM)
	_label(content, "Tab  Orbit / first person   •   Esc  Release mouse", 12, DIM)
	inspection_panel = _panel(Vector2(-358, 130), Vector2(328, 199))
	inspection_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	inspection_panel.offset_left = -358
	inspection_panel.offset_right = -30
	inspection_panel.offset_top = 130
	inspection_panel.offset_bottom = 329
	var inspection_stack = VBoxContainer.new()
	inspection_stack.add_theme_constant_override("separation", 5)
	inspection_panel.add_child(inspection_stack)
	frame_label = _label(inspection_stack, "ANIMATION INSPECTOR", 13, ACCENT)
	clip_label = _label(inspection_stack, "Zombie_Idle · frame 000 / 180", 12, INK)
	clip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clip_label.custom_minimum_size = Vector2(290, 30)
	action_picker = OptionButton.new()
	action_picker.name = "ActionPicker"
	action_picker.custom_minimum_size = Vector2(290, 32)
	action_picker.focus_mode = Control.FOCUS_NONE
	action_picker.add_theme_font_size_override("font_size", 14)
	action_picker.tooltip_text = "Preview any animation in this revision. The R4 demonstration runs the live controller."
	action_picker.item_selected.connect(_on_action_selected)
	inspection_stack.add_child(action_picker)
	var inspect_actions = HBoxContainer.new()
	inspect_actions.add_theme_constant_override("separation", 6)
	inspection_stack.add_child(inspect_actions)
	_command_button(inspect_actions, "Pause / play", _toggle_pause_from_ui)
	_command_button(inspect_actions, "−1 frame", _step_animation.bind(-1))
	_command_button(inspect_actions, "+1 frame", _step_animation.bind(1))
	collider_label = _label(inspection_stack, "C  Show collision shapes", 12, DIM)
	collider_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	collider_label.custom_minimum_size = Vector2(290, 30)
	var target_panel = _panel(Vector2(-320, -123), Vector2(290, 93))
	target_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	target_panel.offset_left = -320
	target_panel.offset_right = -30
	target_panel.offset_top = -123
	target_panel.offset_bottom = -30
	var target_stack = VBoxContainer.new()
	target_stack.add_theme_constant_override("separation", 5)
	target_panel.add_child(target_stack)
	limb_label = _label(target_stack, "AIM AT A LIMB", 13, ACCENT)
	health_label = _label(target_stack, "Local health / structural damage", 12, DIM)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size.y = 4
	hp_bar.show_percentage = false
	hp_bar.max_value = 100
	hp_bar.value = 0
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.11, 0.16, 0.15)
	var fg = StyleBoxFlat.new()
	fg.bg_color = ACCENT
	hp_bar.add_theme_stylebox_override("background", bg)
	hp_bar.add_theme_stylebox_override("fill", fg)
	target_stack.add_child(hp_bar)
	message_label = _label(ui, "", 14, INK)
	message_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	message_label.offset_left = -240
	message_label.offset_right = 360
	message_label.offset_top = -86
	message_label.offset_bottom = -30
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# A restrained reticle keeps thin limbs visible at close range.
	reticle = Control.new()
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	ui.add_child(reticle)
	for bounds in [Rect2(-9, -0.5, 5, 1), Rect2(4, -0.5, 5, 1), Rect2(-0.5, -9, 1, 5), Rect2(-0.5, 4, 1, 5)]:
		var line = ColorRect.new()
		line.position = bounds.position
		line.size = bounds.size
		line.color = Color(0.8, 0.83, 0.77, 0.75)
		reticle.add_child(line)
	hit_indicator = _label(ui, "×", 29, Color(0.86, 0.39, 0.22))
	hit_indicator.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hit_indicator.offset_left = -16
	hit_indicator.offset_right = 16
	hit_indicator.offset_top = -21
	hit_indicator.offset_bottom = 21
	hit_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hit_indicator.hide()
	mouse_label = _label(ui, "CLICK SCENE TO ENTER   ·   ESC RELEASES MOUSE", 13, ACCENT)
	mouse_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	mouse_label.offset_left = -290
	mouse_label.offset_right = 290
	mouse_label.offset_top = 34
	mouse_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ignore_hud_input(ui)
	# Only interactive controls consume clicks; labels still allow scene input.
	for button in revision_buttons.values():
		button.mouse_filter = Control.MOUSE_FILTER_STOP
	for button in ui_action_buttons:
		button.mouse_filter = Control.MOUSE_FILTER_STOP
	action_picker.mouse_filter = Control.MOUSE_FILTER_STOP


func _toggle_pause_from_ui() -> void:
	if is_instance_valid(demonstration) and demonstration.active:
		demonstration.stop()
	_set_animation_paused(not animation_paused)


func _ignore_hud_input(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_hud_input(child)


func _update_ui() -> void:
	inspection_panel.visible = true
	_update_demonstration_ui()
	if is_instance_valid(subject):
		state_label.text = "SUBJECT %02d   •   %s" % [subject_count, "ACTIVE" if subject.alive else "DOWN"]
		state_label.modulate = Color.WHITE if subject.alive else Color(0.94, 0.55, 0.39)
		var missing_count = 0
		for part in subject.missing:
			if subject.missing[part]:
				missing_count += 1
		status_label.text = "%d / 14 PARTS REMAIN" % (14 - missing_count)
		mode_label.text = ("ORBIT" if inspecting else "FIRST PERSON") + "  /  " + (str(subject.state).to_upper() if behavior_on or not subject.alive else current_clip)
		if is_instance_valid(demonstration) and demonstration.active:
			mode_label.text = "LIVE DEMO  /  " + str(subject.state).to_upper()
		if behavior_on and not inspecting and subject.alive:
			mode_label.text = str(subject.state).to_upper() + "  /  PLAYER %d HP" % roundi(player_health)
		if subject.alive and subject.animation_player != null:
			var animation: AnimationPlayer = subject.animation_player
			var clip = animation.get_animation(animation.assigned_animation)
			var actual_action = action_names.find(String(animation.assigned_animation).get_file())
			if actual_action >= 0 and action_picker.selected != actual_action and not action_picker.get_popup().visible:
				action_picker.select(actual_action)
			var animation_position = animation.current_animation_position if not String(animation.current_animation).is_empty() else 0.0
			var frame = inspection_frame if animation_paused else roundi(animation_position * INSPECTION_FPS)
			var last_frame = roundi(clip.length * INSPECTION_FPS) if clip != null else 0
			var playback_state = "PAUSED" if animation_paused else ("PLAYING" if animation.is_playing() else "END")
			frame_label.text = playback_state + "  ·  FRAME %03d / %03d" % [frame, last_frame]
			clip_label.text = "%s  ·  %.3f s  ·  60 Hz" % [String(animation.assigned_animation).get_file(), float(frame) / INSPECTION_FPS]
			collider_label.text = ("GOLD  Rig proxies · CYAN  Physical debris" if not subject.detached_parts.is_empty() else "GOLD  Rig proxies · inactive while animated") if show_colliders else "P  Pause / resume  ·  , / .  Step 1 frame"
		else:
			frame_label.text = "RAGDOLL  ·  PHYSICS RUNNING"
			clip_label.text = "Animation stopped · R resets the subject"
			collider_label.text = "CYAN  Active collision shapes" if show_colliders else "C  Show current physics collision shapes"
	if is_instance_valid(aim_subject) and not aim_part.is_empty():
		limb_label.text = str(PART_NAMES.get(aim_part, aim_part))
		var health = float(aim_subject.limb_health.get(aim_part, 0.0))
		var maximum = float(maximum_limb_health.get(aim_part, 100.0))
		var alternate = "ragdoll" if aim_part == "torso" else "sever"
		health_label.text = "%d / %d health  ·  RMB: %s" % [roundi(health), roundi(maximum), alternate]
		hp_bar.max_value = maximum
		hp_bar.value = health
		reticle.modulate = ACCENT
	else:
		limb_label.text = "AIM AT A LIMB"
		health_label.text = "Local health / structural damage"
		hp_bar.value = 0
		reticle.modulate = Color.WHITE
	hit_indicator.visible = hit_time > 0.0
	message_label.visible = message_time > 0.0
	mouse_label.visible = Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and capture_path.is_empty() and not recording_review


func _update_demonstration_ui() -> void:
	if not is_instance_valid(demonstration):
		return
	var demo: Dictionary = demonstration.get_snapshot()
	demo_start_button.disabled = bool(demo.active)
	demo_stop_button.disabled = not bool(demo.active)
	demo_restart_button.disabled = int(demo.cycle) == 0
	demo_start_button.text = "▶   R4 demonstration running" if demo.active else "▶   Run R4 demonstration"
	if int(demo.cycle) > 0:
		if demo.active:
			var number = mini(int(demo.stage_index) + 1, 9)
			demo_stage_label.text = "CYCLE %d   ·   STATION %d / 9\n%s" % [demo.cycle, number, demonstration.TITLES.get(demo.stage, demo.stage)]
		else:
			demo_stage_label.text = String(demo.note)
		demo_contact_label.text = "LIVE TARGET   %d HP   ·   %d CONTACTS" % [roundi(float(demo.target_health)), int(demo.contacts)]
		if demo.active and is_instance_valid(subject):
			var live: Dictionary = subject.get_behavior_snapshot()
			var action = String(live.get("active_action", ""))
			var movement = String(live.get("movement_mode", "standing"))
			demo_note_label.text = "%s  ·  %s\nLast contact: %s%s" % [movement.capitalize(), _action_label(action) if not action.is_empty() else str(subject.state).replace("_", " "), _action_label(String(demo.last_action)), " · %d damage" % roundi(float(demo.last_damage)) if float(demo.last_damage) > 0.0 else ""]
		else:
			demo_note_label.text = "Orbit and frame inspection remain available.\nRun / Restart restores a complete R4 subject."


func _set_message(value: String, duration: float = 3.0) -> void:
	if is_instance_valid(message_label):
		message_label.text = value
	message_time = duration


func _burst(point: Vector3, normal: Vector3, flesh: bool, count: int) -> void:
	var material = _material(Color(0.30, 0.045, 0.026) if flesh else Color(0.64, 0.43, 0.18), 0.87)
	for i in range(count):
		var mesh = SphereMesh.new()
		mesh.radius = randf_range(0.009, 0.021)
		mesh.height = mesh.radius * 2.0
		mesh.radial_segments = 4
		mesh.rings = 2
		var bit = MeshInstance3D.new()
		bit.mesh = mesh
		bit.material_override = material
		add_child(bit)
		bit.global_position = point + normal * 0.02
		var velocity = normal * randf_range(0.4, 1.1) + Vector3(randf_range(-0.65, 0.65), randf_range(0.4, 1.2), randf_range(-0.65, 0.65))
		effects.append({"node": bit, "velocity": velocity, "life": 0.48})


func _update_effects(delta: float) -> void:
	for i in range(effects.size() - 1, -1, -1):
		var effect: Dictionary = effects[i]
		effect.life -= delta
		if effect.life <= 0 or not is_instance_valid(effect.node):
			if is_instance_valid(effect.node):
				effect.node.queue_free()
			effects.remove_at(i)
		else:
			effect.velocity.y -= delta * 6.5
			effect.node.position += effect.velocity * delta


func _build_audio() -> void:
	# A tiny synthesized impact pulse; there are no downloaded audio assets.
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var bytes = PackedByteArray()
	bytes.resize(3307 * 2)
	var generator = RandomNumberGenerator.new()
	generator.seed = 4932
	for n in range(3307):
		var t = float(n) / 22050.0
		var envelope = exp(-t * 37.0)
		var sample = (sin(t * (110.0 - t * 260.0) * TAU) * 0.37 + generator.randf_range(-1.0, 1.0) * 0.15) * envelope
		bytes.encode_s16(n * 2, int(sample * 32767))
	stream.data = bytes
	shot_sound = AudioStreamPlayer.new()
	shot_sound.stream = stream
	shot_sound.volume_db = -10.0
	add_child(shot_sound)


func _capture_scene() -> void:
	# Optional command line capture for reviewing the actual running Godot scene.
	var scenario = "intact"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scenario="):
			scenario = arg.trim_prefix("--scenario=")
	for i in range(roundi(0.4 * Engine.physics_ticks_per_second)):
		await get_tree().physics_frame
	if is_instance_valid(subject):
		if scenario == "sever":
			subject.sever_limb("forearm_l", Vector3(-0.7, 0.5, 0.6))
		elif scenario == "ragdoll":
			subject.die(Vector3(0.5, 0, -1.0))
		elif scenario == "thigh":
			subject.sever_limb("thigh_l", Vector3(0.5, 0.25, 0.5))
		elif scenario == "attack" and subject.has_method("play_clip"):
			subject.play_clip("Zombie_Attack")
			current_clip = "ATTACK"
		elif scenario == "walk" and subject.has_method("play_clip"):
			subject.play_clip("Zombie_Walk")
			current_clip = "SHAMBLE"
		elif scenario == "hit" and subject.has_method("play_clip"):
			subject.play_clip("Zombie_Hit")
			current_clip = "HIT REACTION"
	if scenario != "intact":
		var settle_ticks = 240 if scenario in ["ragdoll", "thigh"] else 75
		if scenario == "attack":
			settle_ticks = 42
		elif scenario == "walk":
			settle_ticks = 23
		elif scenario == "hit":
			settle_ticks = 12
		elif scenario == "portrait":
			settle_ticks = 24
		# Scenario timing is expressed in 60 Hz animation frames, independent of the physics solver rate.
		for i in range(roundi(float(settle_ticks) / 60.0 * Engine.physics_ticks_per_second)):
			await get_tree().physics_frame
		if scenario == "attack":
			_set_animation_paused(true)
			_seek_animation_frame(42)
	if scenario in ["ragdoll", "thigh"]:
		_set_inspecting(true)
		inspect_yaw = 0.30
		inspect_pitch = 0.56
		inspect_distance = 3.1
		_update_inspect_camera()
		_set_message("Leg lost · living crawl response active. R restores the subject." if subject.alive else "Subject down · physical ragdoll active. R creates a fresh subject.", 5.0)
		await get_tree().physics_frame
	elif scenario == "portrait":
		_set_inspecting(true)
		inspect_yaw = 0.12
		inspect_pitch = 0.08
		inspect_distance = 2.55
		_update_inspect_camera()
		_set_message("Intact subject · full-body orbit inspection.", 5.0)
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	var result = get_viewport().get_texture().get_image().save_png(capture_path)
	print("[ZombieLab] Capture: ", capture_path, " (", result, ")")
	get_tree().quit(0 if result == OK else 3)


func _record_review() -> void:
	# A continuous simulation for Godot's built-in movie writer, not a sequence of stills.
	if not is_instance_valid(subject) or not subject.initialized:
		get_tree().quit(4)
		return
	print("[ZombieLab] Review phase: intact idle")
	_set_message("INTACT · 14 damage regions · animated skeleton", 2.0)
	await _review_hold(1.0, 0.16, 0.08, 2.8)
	print("[ZombieLab] Review phase: pursue and shamble")
	behavior_on = true
	subject.set_behavior(true)
	_set_message("SHAMBLE · live pursuit and locomotion", 2.0)
	await _review_hold(1.8, 0.50, 0.10, 2.9)
	behavior_on = false
	subject.set_behavior(false)
	subject.play_clip("Zombie_Attack")
	current_clip = "ATTACK"
	print("[ZombieLab] Review phase: attack")
	_set_message("ATTACK · wind-up, forward rake and recovery", 1.7)
	await _review_hold(1.6, 0.14, 0.08, 2.85)
	print("[ZombieLab] Review phase: hit reaction")
	_select_clip(3)
	_set_message("HIT · recoil and recovery", 0.7)
	await _review_hold(0.6, 0.10, 0.08, 2.85)
	print("[ZombieLab] Review phase: paused frame inspection and dormant proxies")
	_select_clip(2)
	_set_animation_paused(true)
	_seek_animation_frame(42)
	show_colliders = true
	collision_overlay.show()
	_set_message("PAUSED · exact 60 Hz frame step · gold proxies are inactive during animation", 1.1)
	await _review_hold(0.5, -0.15, 0.09, 2.85)
	_step_animation(1)
	await _review_hold(0.4, -0.10, 0.09, 2.85)
	show_colliders = false
	collision_overlay.hide()
	animation_paused = false
	subject.play_clip("Zombie_Idle")
	current_clip = "IDLE"
	await _review_hold(0.15, 0.12, 0.09, 2.85)
	print("[ZombieLab] Review phase: forearm sever; subject stays alive")
	subject.sever_limb("forearm_l", Vector3(-0.55, 0.4, 0.6))
	shot_sound.play()
	_set_message("FOREARM SEVERED · detached piece is physical · subject remains active", 2.1)
	await _review_hold(1.5, 0.22, 0.12, 3.0)
	print("[ZombieLab] Review phase: native articulated ragdoll")
	subject.die(Vector3(0.18, 0.0, 0.45))
	_set_message("RAGDOLL · articulated physics and floor contacts", 3.0)
	await _review_hold(2.5, 0.42, 0.50, 3.0)
	show_colliders = true
	collision_overlay.show()
	_set_message("PHYSICS INSPECTION · cyan wireframes follow the active collision shapes", 1.3)
	await _review_hold(1.2, 0.46, 0.56, 3.0)
	show_colliders = false
	collision_overlay.hide()
	_set_message("Subject down · connected body physics and physical detached limb", 1.5)
	await _review_hold(1.3, 0.49, 0.56, 3.0)
	print("[ZombieLab] Review finished; continuous simulated duration 12.55 seconds.")
	get_tree().quit(0)


func _review_hold(seconds: float, yaw_to: float, pitch_to: float, distance_to: float) -> void:
	var ticks = roundi(seconds * Engine.physics_ticks_per_second)
	var yaw_from = inspect_yaw
	var pitch_from = inspect_pitch
	var distance_from = inspect_distance
	for i in range(ticks):
		var t = smoothstep(0.0, 1.0, float(i + 1) / float(ticks))
		inspect_yaw = lerpf(yaw_from, yaw_to, t)
		inspect_pitch = lerpf(pitch_from, pitch_to, t)
		inspect_distance = lerpf(distance_from, distance_to, t)
		await get_tree().physics_frame

