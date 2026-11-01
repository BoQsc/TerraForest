# SPDX-License-Identifier: 0BSD
extends RefCounted
## Startup-only visual import. One shared Mesh per definition, never per placement.
const BUILTIN_DOOR := "res://addons/structures/prefabs/door_model.tres"
const MAX_FILE_BYTES := 16 * 1024 * 1024
const MAX_VERTICES := 32768
const MAX_SURFACES := 8
const MAX_IMAGE_PIXELS := 4 * 2048 * 2048
var error := ""
var cache: Dictionary = {}

func load_visual(visual: Dictionary, directory: String) -> Mesh:
	error = ""
	var key := directory + JSON.stringify(visual)
	if cache.has(key): return cache[key]
	var pose := Transform3D(Basis.from_euler(_vector(visual.get("rotation_degrees", [0,0,0])) * PI / 180.0).scaled(_vector(visual.get("scale", [1,1,1]))), _vector(visual.get("offset", [0,0,0])))
	var result: Mesh
	if visual.source == "builtin:wooden_door":
		var original: Mesh = load(BUILTIN_DOOR)
		if pose == Transform3D.IDENTITY:
			result = original
		else:
			# Merge discards incoming LODs. Feed base surfaces deliberately and
			# regenerate once for the normalized visual, including scaled mod doors.
			var base := ImporterMesh.new()
			for surface in original.get_surface_count():
				base.add_surface(Mesh.PRIMITIVE_TRIANGLES,original.surface_get_arrays(surface),[],{},original.surface_get_material(surface),original.surface_get_name(surface))
			var sources: Array[ImporterMesh] = [base]
			var transforms: Array[Transform3D] = [pose]
			var merged := ImporterMesh.merge_importer_meshes(sources, transforms)
			merged.generate_lods(60.0,60.0,[])
			result = merged.get_mesh()
	else:
		result = _load_glb(directory.path_join(visual.source), pose)
	if result != null: cache[key] = result
	return result

static func _vector(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

func _fail(message: String) -> Mesh:
	error = message
	return null

func _load_glb(path: String, visual_pose: Transform3D) -> Mesh:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES or file.get_length() < 20:
		return _fail("GLB missing or outside the 16 MiB file limit: " + path)
	var bytes := file.get_buffer(file.get_length())
	if bytes.decode_u32(0) != 0x46546c67 or bytes.decode_u32(4) != 2 or bytes.decode_u32(8) != bytes.size() or bytes.decode_u32(16) != 0x4e4f534a:
		return _fail("Expected a glTF 2 binary with a JSON first chunk")
	var length := bytes.decode_u32(12)
	if length > bytes.size() - 20: return _fail("Invalid GLB JSON length")
	var json: Variant = JSON.parse_string(bytes.slice(20, 20 + length).get_string_from_utf8())
	if not json is Dictionary: return _fail("Invalid GLB JSON")
	# Loose packs are data-only and self-contained; do not follow external URIs.
	for field in ["buffers", "images"]:
		if not json.get(field, []) is Array: return _fail("Invalid GLB " + field)
		for entry: Variant in json.get(field, []):
			if not entry is Dictionary or entry.has("uri"): return _fail("GLB buffers and textures must be embedded")
	if not json.get("nodes", []) is Array or json.get("nodes", []).size() > 256:
		return _fail("GLB exceeds 256 nodes")
	if not json.get("animations", []) is Array or not json.get("skins", []) is Array: return _fail("Invalid GLB animation/skin arrays")
	if json.get("images", []).size() > 8 or not json.get("animations", []).is_empty() or not json.get("skins", []).is_empty():
		return _fail("Doors accept rigid geometry and up to eight embedded images; no skins or animations")
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_buffer(bytes, path.get_base_dir(), state) != OK:
		return _fail("Godot could not decode GLB: " + path)
	var image_pixels := 0
	for texture: Texture2D in state.get_images():
		if texture != null and (texture.get_width() > 2048 or texture.get_height() > 2048):
			return _fail("Door textures must be at most 2048 by 2048")
		if texture != null: image_pixels += texture.get_width() * texture.get_height()
	if image_pixels > MAX_IMAGE_PIXELS: return _fail("Door exceeds the aggregate 16-megapixel texture budget")
	var nodes := state.get_nodes()
	var meshes := state.get_meshes()
	var sources: Array[ImporterMesh] = []
	var transforms: Array[Transform3D] = []
	var vertices := 0
	var surfaces := 0
	# Traverse only the selected scene, rejecting cycles/shared node ownership.
	var pending: Array[Dictionary] = []
	for index: int in state.root_nodes: pending.append({"index":index, "pose":visual_pose})
	var visited := {}
	while not pending.is_empty():
		var item: Dictionary = pending.pop_back()
		var index: int = item.index
		if index < 0 or index >= nodes.size() or visited.has(index): return _fail("Invalid GLB node hierarchy")
		visited[index] = true
		var node: GLTFNode = nodes[index]
		var pose: Transform3D = item.pose * node.xform
		if not pose.is_finite() or pose.basis.determinant() <= 0.000001:
			return _fail("Bake mirrored or singular transforms before exporting the door")
		for child: int in node.children: pending.append({"index":child, "pose":pose})
		if node.mesh < 0: continue
		if node.mesh >= meshes.size() or node.skin >= 0: return _fail("Invalid rigid GLB mesh")
		var mesh: ImporterMesh = meshes[node.mesh].mesh
		if mesh == null or mesh.get_blend_shape_count() != 0: return _fail("Door morph targets are unsupported")
		for surface in mesh.get_surface_count():
			if mesh.get_surface_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: return _fail("Door surfaces must use triangles")
			vertices += mesh.get_surface_arrays(surface)[Mesh.ARRAY_VERTEX].size()
			surfaces += 1
		if vertices > MAX_VERTICES or surfaces > MAX_SURFACES: return _fail("Door exceeds 32768 vertices or eight surfaces")
		sources.append(mesh)
		transforms.append(pose)
	if sources.is_empty(): return _fail("GLB has no rigid mesh in its selected scene")
	var merged := ImporterMesh.merge_importer_meshes(sources, transforms)
	if merged == null: return _fail("Could not consolidate the door meshes")
	# Godot's native importer derives LODs once, before gameplay begins.
	merged.generate_lods(60.0, 60.0, [])
	var result := merged.get_mesh()
	if result == null or result.get_aabb().size.length() > 32: return _fail("Door visual exceeds the 32 metre bounds limit")
	return result
