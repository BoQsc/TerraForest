# SPDX-License-Identifier: 0BSD
extends Node3D
## Camera-local presentation. The existing native motor remains the player owner.
const MODEL = preload("res://addons/characters/runtime/assets/Human.r11.glb")
const HIDDEN_SURFACE = preload("res://addons/characters/runtime/hidden_surface.gdshader")
var model: Node3D
var animation_player: AnimationPlayer
var meshes: Array[MeshInstance3D] = []
var clips: Dictionary = {}
var current := 0
var active_clip := ""
var action_remaining := 0.0
var body: CharacterBody3D

func _ready() -> void:
	# Inverse of the source viewer's FP camera (0, 1.65, .03), facing +Z.
	position = Vector3(0, -1.65, 0.03)
	rotation.y = PI
	model = MODEL.instantiate()
	add_child(model)
	_collect(model)
	for clip in animation_player.get_animation_list():
		clips[String(clip).get_slice("/", String(clip).get_slice_count("/") - 1)] = clip
	equip(current)

func _collect(node: Node) -> void:
	if node is AnimationPlayer:
		animation_player = node
	if node is MeshInstance3D:
		meshes.append(node)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# The source body combines skin and head in one skinned mesh. Hide only
		# its head/mouth surfaces so the FP camera cannot see inside the face.
		for index in node.mesh.get_surface_count():
			var material: Material = node.mesh.surface_get_material(index)
			if material != null and ("Human.Head" in material.resource_name or "Human.Mouth" in material.resource_name):
				var hidden := ShaderMaterial.new();hidden.shader = HIDDEN_SURFACE
				node.set_surface_override_material(index, hidden)
	for child in node.get_children():
		_collect(child)

func equip(item: int) -> void:
	current = item
	action_remaining = 0.0
	if model == null:
		return
	for mesh in meshes:
		var label := String(mesh.name).to_lower().replace("_", ".")
		if label.begins_with("equipment."):
			mesh.visible = (item == 1 and label.contains("pickaxe")) or (item == 2 and label.contains("axe") and not label.contains("pickaxe"))
		elif label.begins_with("hair.") or label.begins_with("brows.") or label.begins_with("eye") or label.begins_with("upper_lashes"):
			mesh.hide()
	_play(_motion_clip("Idle"))

func _motion_clip(action: String) -> String:
	var prefix := "FP_Pickaxe_" if current == 1 else ("FP_Axe_" if current == 2 else "")
	return prefix + action if clips.has(prefix + action) else action

func _play(clip: String, once: bool = false) -> void:
	if not clips.has(clip):
		return
	if active_clip != clip or not animation_player.is_playing():
		animation_player.play(clips[clip], 0.10)
		active_clip = clip
	if once:
		action_remaining = animation_player.get_animation(clips[clip]).length

func swing() -> void:
	if action_remaining > 0.0:
		return
	var clip := _motion_clip("Swing")
	if clips.has(clip):
		_play(clip, true)

func _process(delta: float) -> void:
	animation_player.active = is_visible_in_tree()
	if not animation_player.active:
		return
	if action_remaining > 0.0:
		action_remaining = maxf(0.0, action_remaining - delta)
		if action_remaining > 0.0:
			return
	var motion := "Idle"
	if is_instance_valid(body):
		var speed := Vector2(body.velocity.x, body.velocity.z).length()
		if not body.is_on_floor() and absf(body.velocity.y) > 0.5:
			motion = "Jump"
		elif speed > 0.15:
			motion = "Run" if speed > 5.0 else "Walk"
	_play(_motion_clip(motion))
