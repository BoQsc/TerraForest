# SPDX-License-Identifier: CC0-1.0
# Installs a separate upper-body player without editing the model or its original clips.
extends RefCounted

const Definition = preload("item_definition.gd")

static func validate_contract(model: Node, library: AnimationLibrary, expected: Dictionary) -> Dictionary:
	if model == null or library == null or not library.has_meta("item_human_bones"):
		return {"passed":false,"error":"AnimationLibrary has no verified human rest contract. Rebuild it with import_item_animations.gd."}
	var skeleton := model.get_node_or_null(NodePath(String(library.get_meta("item_human_skeleton_path", "")))) as Skeleton3D
	if skeleton == null:
		return {"passed":false,"error":"The existing Human model does not have the verified skeleton path."}
	var bones: Array = library.get_meta("item_human_bones")
	if skeleton.get_bone_count() != bones.size() or skeleton.get_bone_count() != int(expected.get("expected_bones", bones.size())):
		return {"passed":false,"error":"The existing Human bone count differs from the verified animation target."}
	var tolerance := float(expected.get("reference_rest_tolerance", 0.0001))
	var maximum := 0.0
	for index in bones.size():
		var record: Dictionary = bones[index]
		if skeleton.get_bone_name(index) != String(record["name"]) or skeleton.get_bone_parent(index) != int(record["parent"]):
			return {"passed":false,"error":"Human bone names/order/parents differ at bone " + str(index)}
		var actual := skeleton.get_bone_rest(index)
		var declared: Transform3D = record["rest"]
		maximum = maxf(maximum, actual.origin.distance_to(declared.origin))
		for column in 3:
			for row in 3:
				maximum = maxf(maximum, absf(actual.basis[column][row] - declared.basis[column][row]))
	if maximum > tolerance:
		return {"passed":false,"error":"Human rest transforms differ from the verified animation target.","maximum_rest_error":maximum}
	return {"passed":true,"error":"","maximum_rest_error":maximum,"skeleton":skeleton}

static func install(model: Node, library: AnimationLibrary) -> AnimationPlayer:
	if model == null or library == null:
		return null
	var player := AnimationPlayer.new()
	player.name = "FirstPersonItemAnimation"
	model.add_child(player)
	player.root_node = NodePath("..")
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if player.add_animation_library("", library) != OK:
		player.queue_free()
		return null
	return player

static func save_and_neutralize_body_shapes(model: Node, mesh_names: Array = ["Human_Body"]) -> Array:
	var snapshot: Array = []
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if String(mesh.name) not in mesh_names or mesh.mesh == null:
			continue
		var values := PackedFloat32Array()
		for index in mesh.get_blend_shape_count():
			values.append(mesh.get_blend_shape_value(index))
			mesh.set_blend_shape_value(index, 0.0)
		snapshot.append({"mesh": weakref(mesh), "values": values})
	return snapshot

static func enforce_neutral_body_shapes(snapshot: Array) -> void:
	# Call after the base locomotion pose if that player also has morph tracks.
	# Only instance values change; original mesh data and animation resources do not.
	for entry: Dictionary in snapshot:
		var mesh := (entry["mesh"] as WeakRef).get_ref() as MeshInstance3D
		if not is_instance_valid(mesh):
			continue
		for index in mesh.get_blend_shape_count():
			if mesh.get_blend_shape_value(index) != 0.0:
				mesh.set_blend_shape_value(index, 0.0)

static func restore_body_shapes(snapshot: Array) -> void:
	for entry: Dictionary in snapshot:
		var mesh := (entry["mesh"] as WeakRef).get_ref() as MeshInstance3D
		if not is_instance_valid(mesh):
			continue
		var values: PackedFloat32Array = entry["values"]
		for index in mini(values.size(), mesh.get_blend_shape_count()):
			mesh.set_blend_shape_value(index, values[index])

static func apply_mesh_overrides(model: Node, overrides: Array, definition_path: String) -> Dictionary:
	var snapshots: Array = []
	for record: Dictionary in overrides:
		var name := String(record.get("mesh", ""))
		var instance := model.find_child(name, true, false) as MeshInstance3D
		var path := Definition.resolve_file(definition_path, String(record.get("resource", "")))
		var supplied := load(path) as ArrayMesh
		if instance == null or instance.mesh == null or supplied == null:
			restore_meshes(snapshots)
			return {"passed":false,"snapshots":[],"error":"Cannot resolve per-item body mesh override: " + name}
		var original := instance.mesh
		if original.get_surface_count() != supplied.get_surface_count() or original.get_blend_shape_count() != supplied.get_blend_shape_count():
			restore_meshes(snapshots)
			return {"passed":false,"snapshots":[],"error":"Body variant topology/morph structure differs from the active model"}
		for shape in original.get_blend_shape_count():
			if original.get_blend_shape_name(shape) != supplied.get_blend_shape_name(shape):
				restore_meshes(snapshots)
				return {"passed":false,"snapshots":[],"error":"Body variant morph names differ from the active model"}
		var variant := supplied.duplicate(false) as ArrayMesh
		for surface in original.get_surface_count():
			variant.surface_set_material(surface, original.surface_get_material(surface))
		snapshots.append({"mesh":weakref(instance),"original":original})
		instance.mesh = variant
	return {"passed":true,"snapshots":snapshots,"error":""}

static func restore_meshes(snapshots: Array) -> void:
	for entry: Dictionary in snapshots:
		var mesh := (entry["mesh"] as WeakRef).get_ref() as MeshInstance3D
		if is_instance_valid(mesh):
			mesh.mesh = entry["original"]
