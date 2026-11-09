# SPDX-License-Identifier: CC0-1.0
# Small host-facing adapter. Call equip() with an already loaded human and item.
# This consumes the supplied item instance, including on failure; it never owns Human.
extends Node

signal event_reached(event_name: String, details: Dictionary)
signal action_started(action_id: String)
signal action_finished(action_id: String)
signal action_cancelled(action_id: String)

const Definition = preload("item_definition.gd")
const Mount = preload("item_mount.gd")
const Motion = preload("item_motion.gd")
const HumanLayer = preload("item_human_layer.gd")

var auto_process := true
var motion: Node
var item: Node3D
var human_player: AnimationPlayer
var attachment: BoneAttachment3D
var body_shapes: Array = []
var body_meshes: Array = []

func _ready() -> void:
	process_priority = 20

func equip(human_model: Node3D, item_model: Node3D, library: AnimationLibrary,
		definition: Dictionary, definition_path: String) -> Error:
	unequip()
	item = item_model
	if human_model == null or item_model == null or library == null:
		unequip()
		return ERR_INVALID_PARAMETER
	var problems := Definition.validate(definition)
	if not problems.is_empty():
		push_error("Item definition is invalid: " + "; ".join(problems))
		unequip()
		return ERR_INVALID_DATA
	var contract := HumanLayer.validate_contract(human_model, library, definition.get("human", {}))
	if not bool(contract["passed"]):
		push_error(String(contract["error"]))
		unequip()
		return ERR_INVALID_DATA
	var skeleton: Skeleton3D = contract["skeleton"]
	human_player = HumanLayer.install(human_model, library)
	if human_player == null:
		unequip()
		return ERR_CANT_CREATE
	body_shapes = HumanLayer.save_and_neutralize_body_shapes(human_model)
	var overridden := HumanLayer.apply_mesh_overrides(human_model, definition.get("human", {}).get("mesh_overrides", []), definition_path)
	if not bool(overridden["passed"]):
		push_error(String(overridden["error"]))
		unequip()
		return ERR_INVALID_DATA
	body_meshes = overridden["snapshots"]
	attachment = Mount.attach(skeleton, item, definition["mount"])
	if attachment == null:
		unequip()
		return ERR_INVALID_DATA
	motion = Motion.new()
	motion.name = "ItemMotion"
	add_child(motion)
	motion.auto_process = false
	var configured: Error = motion.configure(human_player, Mount.find_player(item), definition)
	if configured != OK:
		unequip()
		return configured
	motion.event_reached.connect(func(name: String, data: Dictionary): event_reached.emit(name, data))
	motion.action_started.connect(func(id: String): action_started.emit(id))
	motion.action_finished.connect(func(id: String): action_finished.emit(id))
	motion.action_cancelled.connect(func(id: String): action_cancelled.emit(id))
	motion.pose_sampled.connect(_after_pose)
	motion.play_action(String(definition["default_action"]))
	return OK

func _after_pose(_id: String, _seconds: float, _frame: float) -> void:
	HumanLayer.enforce_neutral_body_shapes(body_shapes)
	Mount.synchronize(attachment)

func request(action_id: String, blend_seconds: float = 0.0) -> Error:
	return motion.play_action(action_id, blend_seconds) if motion != null else ERR_UNCONFIGURED

func advance(delta: float) -> void:
	# Hosts with manual AnimationTree/locomotion should call this after that pose.
	if motion != null:
		motion.advance(delta)
		HumanLayer.enforce_neutral_body_shapes(body_shapes)

func _process(delta: float) -> void:
	if auto_process:
		advance(delta)

func unequip() -> void:
	if motion != null:
		motion.cancel()
		motion.queue_free()
		motion = null
	if human_player != null:
		human_player.queue_free()
		human_player = null
	if attachment != null:
		attachment.queue_free()
		attachment = null
	elif item != null:
		item.queue_free()
	item = null
	# Replacing a mesh can reset instance shape values. Restore the exact original
	# mesh first, then the captured corrective values. The next item can override.
	HumanLayer.restore_meshes(body_meshes)
	HumanLayer.restore_body_shapes(body_shapes)
	body_meshes.clear()
	body_shapes.clear()

func _exit_tree() -> void:
	unequip()
