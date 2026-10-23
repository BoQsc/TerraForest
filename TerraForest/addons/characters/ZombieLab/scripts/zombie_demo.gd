extends Node3D
## Stateful test stations use the live zombie controller, colliders and limb system.
## Stages advance after controller outcomes; previews never drive this demonstration.

signal stage_changed(stage: String)
signal cycle_completed(summary: Dictionary)

const STAGES = ["approach", "bite", "left", "right", "both", "jump", "ladder", "one_leg", "both_legs", "cycle_complete"]
const TITLES = {
	"approach": "Pursuit · moving target enters reach",
	"bite": "Bite · close target / mouth contact",
	"left": "Left hand · single arm strike",
	"right": "Right hand · opposite arm strike",
	"both": "Both hands · committed two arm attack",
	"jump": "Obstacle · short hop with a real landing",
	"ladder": "Ladder · alternating rungs / platform exit",
	"one_leg": "One leg lost · drop, crawl and bite",
	"both_legs": "Both legs lost · living crawl pursuit",
	"cycle_complete": "Cycle complete · restoring in 4 seconds"
}
const LADDER_BASE = Vector3(3.0, 0.0, -2.0)
const LADDER_ROOT = Vector3(3.0, 0.025, -2.40)
const LADDER_EXIT = Vector3(3.85, 0.925, -2.45)
const JUMP_START = Vector3(2.35, 0.025, -3.60)
const ATTACK_STAND_OFF = {"bite": 0.636, "left": 1.017, "right": 1.050, "both": 0.971}

var lab
var target
var active = false
var stage = "stopped"
var stage_time = 0.0
var cycle = 0
var elapsed = 0.0
var target_destination = Vector3.ZERO
var target_speed = 1.3
var stage_requested = false
var stage_finished = false
var stage_contact = false
var stage_attempts = 0
var contact_count = 0
var last_action = "—"
var last_damage = 0.0
var status_note = "Start selects F4 / R4 and restores all limbs."
var stage_origin = Vector3.ZERO
var stage_distance = 0.0
var jump_peak = 0.0
var jump_end = Vector3.ZERO
var ladder_end = Vector3.ZERO
var complete = false
var completed_cycles: Array = []
var contact_events: Array = []
var station_events: Array = []
var props: Node3D
var prop_bodies: Array[StaticBody3D] = []
var _cycle_summary: Dictionary = {}


func _ready() -> void:
	name = "ZombieDemonstration"
	_build_props()
	target = load("res://scripts/zombie_demo_target.gd").new()
	add_child(target)
	target.struck.connect(_on_target_struck)
	_set_environment_enabled(false)


func start() -> bool:
	if lab == null:
		return false
	if active:
		stop(true)
	var changed_revision = lab.selected_revision != "r4"
	if changed_revision:
		lab.select_revision("r4")
	if lab.selected_revision != "r4":
		return false
	lab.behavior_on = false
	if not changed_revision and not lab._spawn_subject():
		return false
	if not lab.subject.has_method("request_attack") or not lab.subject.has_method("request_climb"):
		status_note = "R4 behavior controller is unavailable."
		return false
	active = true
	complete = false
	cycle = 1
	elapsed = 0.0
	completed_cycles.clear()
	_start_cycle(false)
	lab._set_inspecting(true)
	lab.inspect_yaw = 0.64
	lab.inspect_pitch = 0.12
	lab.inspect_distance = 4.9
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	lab._set_message("R4 demonstration running. Contacts, jump, ladder and limb loss use the live controller. Stop leaves the current subject available.", 6.0)
	return true


func stop(clear_environment: bool = false) -> void:
	if is_instance_valid(lab.subject):
		lab.subject.set_behavior(false)
		if lab.subject.has_method("cancel_traversal"):
			lab.subject.cancel_traversal()
		lab.subject.target = lab.player
		lab.subject.velocity.x = 0.0
		lab.subject.velocity.z = 0.0
	lab.behavior_on = false
	active = false
	stage = "stopped"
	status_note = "Stopped. R resets the subject; Run starts a fresh cycle."
	if clear_environment:
		_set_environment_enabled(false)
	elif is_instance_valid(target):
		# Keep the platform under a subject who stopped after a ladder exit.
		target.set_enabled(false)


func restart() -> bool:
	return start()


func _start_cycle(respawn: bool) -> void:
	if respawn:
		lab.behavior_on = false
		lab._spawn_subject()
	var zombie = lab.subject
	zombie.target = target
	if zombie.has_signal("attack_contact") and not zombie.attack_contact.is_connected(_on_attack_contact):
		zombie.attack_contact.connect(_on_attack_contact)
	if zombie.has_signal("action_finished") and not zombie.action_finished.is_connected(_on_action_finished):
		zombie.action_finished.connect(_on_action_finished)
	target.reset()
	contact_count = 0
	contact_events.clear()
	station_events.clear()
	last_action = "—"
	last_damage = 0.0
	complete = false
	_set_environment_enabled(true)
	_place_subject(Vector3(0, 0.025, -0.80), 0.0)
	target.global_position = Vector3(0, 0, 2.20)
	target_destination = target.global_position
	_enter_stage("approach")


func _place_subject(at: Vector3, yaw: float) -> void:
	var zombie = lab.subject
	zombie.set_behavior(false)
	if zombie.has_method("cancel_traversal"):
		zombie.cancel_traversal()
	zombie.global_position = at
	zombie.rotation.y = yaw
	zombie.velocity = Vector3.ZERO
	lab.animation_paused = false
	lab.behavior_on = false


func _enter_stage(next_stage: String) -> void:
	stage = next_stage
	stage_time = 0.0
	stage_requested = false
	stage_finished = false
	stage_contact = false
	stage_attempts = 0
	stage_origin = lab.subject.global_position
	stage_distance = 0.0
	status_note = String(TITLES.get(stage, stage))
	station_events.append({"stage": stage, "elapsed": elapsed, "root": _v3(lab.subject.global_position)})
	var zombie = lab.subject
	target.set_contact_action(stage)
	match stage:
		"approach":
			lab.behavior_on = true
			zombie.set_behavior(true)
		"bite", "left", "right", "both":
			lab.behavior_on = false
			zombie.set_behavior(false)
			zombie.velocity.x = 0.0
			zombie.velocity.z = 0.0
			var reach = float(ATTACK_STAND_OFF[stage])
			target_destination = zombie.global_position + zombie.global_basis.z * reach
			target_destination.y = 0.0
		"jump":
			_place_subject(JUMP_START, 0.0)
			stage_origin = JUMP_START
			target.global_position = Vector3(2.35, 0, -2.10)
			target_destination = target.global_position
			jump_peak = zombie.global_position.y
		"ladder":
			_place_subject(LADDER_ROOT, 0.0)
			target.global_position = Vector3(4.50, 0.90, -2.80)
			target_destination = target.global_position
		"one_leg":
			_place_subject(Vector3(0, 0.025, -0.80), 0.0)
			target.set_low_mode(true)
			target.global_position = Vector3(0, 0, 0.90)
			target_destination = target.global_position
			zombie.sever_limb("thigh_l", Vector3(-0.35, 0.10, -0.25))
			lab.behavior_on = true
			zombie.set_behavior(true)
			stage_origin = zombie.global_position
		"both_legs":
			zombie.sever_limb("thigh_r", Vector3(0.35, 0.10, -0.25))
			target_destination = target.global_position + Vector3(0, 0, 0.95)
			lab.behavior_on = true
			zombie.set_behavior(true)
		"cycle_complete":
			zombie.set_behavior(false)
			lab.behavior_on = false
			complete = true
			_cycle_summary = {"cycle": cycle, "contacts": contact_events.duplicate(true), "stations": station_events.duplicate(true), "jump_peak_y": jump_peak, "jump_end": _v3(jump_end), "ladder_end": _v3(ladder_end), "final_alive": zombie.alive, "final_movement_mode": zombie.get_behavior_snapshot().get("movement_mode", ""), "target_health": target.health}
			completed_cycles.append(_cycle_summary)
			cycle_completed.emit(_cycle_summary)
	stage_changed.emit(stage)


func _physics_process(delta: float) -> void:
	if not active:
		return
	if not is_instance_valid(lab.subject) or not lab.subject.alive:
		active = false
		status_note = "Subject down. Restart restores the R4 demonstration."
		return
	var zombie = lab.subject
	stage_time += delta
	elapsed += delta
	var destination_delta: Vector3 = target_destination - target.global_position
	if destination_delta.length() > 0.001:
		target.global_position += destination_delta.limit_length(target_speed * delta)
	var snapshot: Dictionary = zombie.get_behavior_snapshot()
	var active_action = String(snapshot.get("active_action", ""))
	stage_distance = Vector2(zombie.global_position.x - stage_origin.x, zombie.global_position.z - stage_origin.z).length()
	match stage:
		"approach":
			if _target_distance() <= 1.43:
				_enter_stage("bite")
		"bite", "left", "right", "both":
			if not stage_requested and destination_delta.length() < 0.02 and active_action.is_empty() and stage_time > 0.20:
				stage_requested = zombie.request_attack(stage)
				if stage_requested:
					stage_attempts += 1
			if stage_finished:
				if stage_contact:
					_next_stage()
				elif stage_attempts < 3:
					target_destination -= zombie.global_basis.z * 0.045
					stage_requested = false
					stage_finished = false
					status_note = "Target moves closer · waiting for a confirmed contact"
				else:
					_fail("The %s contact did not connect. Restart to retry." % stage)
		"jump":
			jump_peak = maxf(jump_peak, zombie.global_position.y)
			if not stage_requested and stage_time > 0.40:
				stage_requested = zombie.request_jump(1.4)
			if stage_finished and zombie.is_on_floor():
				jump_end = zombie.global_position
				_next_stage()
		"ladder":
			if not stage_requested and stage_time > 0.40:
				stage_requested = zombie.request_climb({"base": LADDER_BASE, "facing": Vector3(0, 0, 1), "height": 0.90, "exit": LADDER_EXIT})
			if stage_finished:
				ladder_end = zombie.global_position
				_next_stage()
		"one_leg", "both_legs":
			if stage_contact and active_action.is_empty() and stage_distance > 0.35:
				_next_stage()
		"cycle_complete":
			if stage_time > 4.0:
				cycle += 1
				_start_cycle(true)
	if active and stage_time > 24.0 and stage != "cycle_complete":
		_fail("Waiting for %s. Restart restores the test stations." % String(TITLES.get(stage, stage)).to_lower())


func _next_stage() -> void:
	var index = STAGES.find(stage)
	if index >= 0 and index + 1 < STAGES.size():
		_enter_stage(STAGES[index + 1])


func _target_distance() -> float:
	var offset: Vector3 = target.global_position - lab.subject.global_position
	return Vector2(offset.x, offset.z).length()


func _on_attack_contact(action: String, damage: float, world_point: Vector3) -> void:
	if not active:
		return
	stage_contact = true
	contact_count += 1
	last_action = action
	last_damage = damage
	var confirmed: Dictionary = lab.subject.get_behavior_snapshot().get("last_contact", {})
	contact_events.append({"stage": stage, "action": action, "damage": damage, "elapsed": elapsed, "point": _v3(world_point), "target": _v3(target.global_position), "root": _v3(lab.subject.global_position), "surface_gap_m": float(confirmed.get("surface_distance", 0.0)), "signed_surface_distance_m": target.get_signed_contact_surface_distance(action, world_point), "visible_target_shapes": bool(confirmed.get("visible_target_shapes", false))})
	lab._burst(world_point, -lab.subject.global_basis.z, false, 5)


func _on_target_struck(_damage: float) -> void:
	if active:
		lab.hit_time = 0.12


func _on_action_finished(action: String) -> void:
	if not active:
		return
	var lower = action.to_lower()
	if stage in ["bite", "left", "right", "both"] and lower.contains(stage):
		stage_finished = true
	elif stage == "jump" and lower.contains("jump"):
		stage_finished = true
	elif stage == "ladder" and (lower.contains("climb") or lower.contains("ladder")):
		stage_finished = true


func _fail(reason: String) -> void:
	lab.subject.set_behavior(false)
	lab.behavior_on = false
	active = false
	status_note = reason
	lab._set_message(reason, 8.0)


func get_snapshot() -> Dictionary:
	return {"active": active, "stage": stage, "stage_index": STAGES.find(stage), "stage_count": STAGES.size() - 1, "stage_time": stage_time, "cycle": cycle, "elapsed": elapsed, "contacts": contact_count, "last_action": last_action, "last_damage": last_damage, "target_health": target.health if is_instance_valid(target) else 100.0, "note": status_note, "complete": complete, "cycles_completed": completed_cycles.size(), "stage_distance": stage_distance, "stage_requested": stage_requested, "stage_finished": stage_finished, "stage_contact": stage_contact}


func _v3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _set_environment_enabled(enabled: bool) -> void:
	props.visible = enabled
	for body in prop_bodies:
		body.collision_layer = 1 if enabled else 0
	if is_instance_valid(target):
		target.set_enabled(enabled)


func _build_props() -> void:
	props = Node3D.new()
	props.name = "DemonstrationStations"
	add_child(props)
	var steel = StandardMaterial3D.new()
	steel.albedo_color = Color(0.22, 0.29, 0.28)
	steel.metallic = 0.40
	steel.roughness = 0.55
	var amber = StandardMaterial3D.new()
	amber.albedo_color = Color(0.73, 0.49, 0.17)
	amber.roughness = 0.70
	_box("HopBarrier", JUMP_START + Vector3(0, 0.025, 0.32), Vector3(1.10, 0.10, 0.06), amber, true)
	_box("LandingPlatform", Vector3(4.10, 0.45, -2.45), Vector3(1.50, 0.90, 1.10), steel, true)
	for x in [2.63, 3.37]:
		_box("LadderRail", Vector3(x, 1.51, -2.0), Vector3(0.045, 3.02, 0.045), steel, true)
	for index in range(10):
		_box("Rung_%02d" % index, Vector3(3.0, float(index) * 0.30, -2.0), Vector3(0.78, 0.036, 0.040), amber, true)
	for x in [-0.35, 0.35]:
		_box("TargetTrack", Vector3(x, 0.009, 1.40), Vector3(0.023, 0.008, 5.00), steel, false)
	_world_text("10 cm HOP", JUMP_START + Vector3(-0.78, 0.04, 0.34), 26, amber.albedo_color)
	_world_text("LADDER  ·  30 cm RUNGS", Vector3(3.0, 3.25, -2.0), 25, amber.albedo_color)


func _box(label: String, at: Vector3, dimensions: Vector3, material: Material, solid: bool) -> void:
	var visual = MeshInstance3D.new()
	visual.name = label
	visual.position = at
	var mesh = BoxMesh.new()
	mesh.size = dimensions
	visual.mesh = mesh
	visual.material_override = material
	props.add_child(visual)
	if solid:
		var body = StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape = CollisionShape3D.new()
		var bounds = BoxShape3D.new()
		bounds.size = dimensions
		shape.shape = bounds
		body.add_child(shape)
		visual.add_child(body)
		prop_bodies.append(body)


func _world_text(value: String, at: Vector3, font_size: int, color: Color) -> void:
	var label = Label3D.new()
	label.text = value
	label.position = at
	label.font_size = font_size
	label.pixel_size = 0.003
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 4
	props.add_child(label)
