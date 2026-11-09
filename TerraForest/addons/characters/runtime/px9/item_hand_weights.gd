# SPDX-License-Identifier: CC0-1.0
# Optional per-item hand skin variant. Geometry, UV, normal, tangent and morph
# buffers are copied byte-for-byte; only eligible skin records are replaced.
extends RefCounted

const POSITION_TOLERANCE := 0.000025
const RAW_GEOMETRY_KEYS := ["vertex_data", "attribute_data", "index_data", "blend_shape_data"]

static func build_variant(body: MeshInstance3D, skeleton: Skeleton3D, patch: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var report := {"schema":"bg5-native-hand-skin-1", "engine":Engine.get_version_info().string,
		"source_patch_schema":patch.get("schema", ""), "source_rows":0,
		"mapped_source_rows":0, "mapped_runtime_vertices":0, "changed_runtime_vertices":0,
		"maximum_position_match_error_metres":0.0, "maximum_weight_quantization_error":0.0,
		"maximum_source_requested_weight_difference":0.0,
		"original_native_non_hand_weights_preserved":true,
		"unpatched_skin_records_byte_identical":true,
		"raw_geometry_and_morph_buffers_byte_identical":true,
		"runtime_materials":"Reused from the original model at equip time; not serialized into the variant.",
		"bounds_policy":"Original per-bone bounds retained and conservatively expanded for newly assigned vertices.",
		"surfaces":[]}
	if body == null or body.skin == null or not body.mesh is ArrayMesh or skeleton == null:
		return _failure(report, ["A skinned original ArrayMesh body and its Skeleton3D are required"])
	if String(patch.get("source_mesh", "")) != String(body.name):
		return _failure(report, ["Patch names a different body mesh"])
	var source := body.mesh as ArrayMesh
	var bind_names: Array[String] = []
	var bind_lookup := {}
	for bind in body.skin.get_bind_count():
		var name := String(body.skin.get_bind_name(bind))
		if name.is_empty():
			var bone := body.skin.get_bind_bone(bind)
			if bone < 0 or bone >= skeleton.get_bone_count():
				return _failure(report, ["Cannot resolve a named source skin bind"])
			name = String(skeleton.get_bone_name(bone))
		bind_names.append(name)
		bind_lookup[name] = bind
	var rows: Array = patch.get("vertices", [])
	if rows.is_empty():
		return _failure(report, ["The hand patch contains no source vertices"])
	report["source_rows"] = rows.size()
	var points := PackedVector3Array()
	var grid := {}
	var mapped := {}
	for index in rows.size():
		var row: Dictionary = rows[index]
		var position: Array = row.get("position_gltf", [])
		if position.size() != 3 or String(row.get("side", "")) not in ["Left", "Right"]:
			return _failure(report, ["Each patch row needs a Godot rest position and Left/Right side"])
		var point := Vector3(position[0], position[1], position[2])
		points.append(point)
		var key := Vector3i((point * 100000.0).round())
		if not grid.has(key): grid[key] = []
		grid[key].append(index)
		var total := 0.0
		for influence: Dictionary in row.get("weights", []):
			var name := String(influence.get("bone", ""))
			var weight := float(influence.get("weight", -1.0))
			if not bind_lookup.has(name) or not is_finite(weight) or weight < 0.0:
				return _failure(report, ["Patch contains an unknown bone or invalid influence"])
			total += weight
		if absf(total - 1.0) > 0.00001:
			return _failure(report, ["Patch source weights are not normalized"])
	var storage: Array = source.get("_surfaces")
	if storage.size() != source.get_surface_count():
		return _failure(report, ["This Godot version does not expose the expected native ArrayMesh serialization"])
	for surface in source.get_surface_count():
		var stored_surface: Dictionary = storage[surface].duplicate(false)
		var native_surface := RenderingServer.mesh_get_surface(source.get_rid(), surface)
		var arrays := source.surface_get_arrays(surface)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var width: int = indices.size() / positions.size()
		var format := source.surface_get_format(surface)
		var stride := RenderingServer.mesh_surface_get_format_skin_stride(format, positions.size())
		var bones_offset := RenderingServer.mesh_surface_get_format_offset(format, positions.size(), Mesh.ARRAY_BONES)
		var weights_offset := RenderingServer.mesh_surface_get_format_offset(format, positions.size(), Mesh.ARRAY_WEIGHTS)
		if width not in [4, 8] or stride != width * 4 or bones_offset != 0 or weights_offset != width * 2:
			return _failure(report, ["Unsupported native skin packing; expected4/8 uint16 binds and weights"])
		var original_skin: PackedByteArray = stored_surface.get("skin_data", PackedByteArray())
		if original_skin.size() != positions.size() * stride:
			return _failure(report, ["Native skin byte count is inconsistent"])
		var skin := original_skin.duplicate()
		var bounds: Array = stored_surface.get("bone_aabbs", []).duplicate()
		while bounds.size() < bind_names.size():
			bounds.append(AABB(Vector3.ZERO, Vector3(-1, -1, -1)))
		var mapped_vertices := 0
		var changed_vertices := 0
		var changed_eligible := {}
		for vertex in positions.size():
			var matches := _match_rows(positions[vertex], points, grid)
			if matches.is_empty():
				continue
			var row: Dictionary = rows[matches[0]]
			for index in matches:
				if rows[index]["weights"] != row["weights"] or rows[index]["side"] != row["side"]:
					return _failure(report, ["Coincident patch rows request different weights; explicit disambiguation is needed"])
				mapped[index] = int(mapped.get(index, 0)) + 1
			var distance := positions[vertex].distance_to(points[matches[0]])
			report["maximum_position_match_error_metres"] = maxf(report["maximum_position_match_error_metres"], distance)
			var start := vertex * stride
			var prefix := String(row["side"]) + "Hand"
			var fixed: Array = []
			var fixed_total := 0
			for slot in width:
				var bind := original_skin.decode_u16(start + bones_offset + slot * 2)
				var units := original_skin.decode_u16(start + weights_offset + slot * 2)
				if units > 0 and not bind_names[bind].begins_with(prefix):
					fixed.append({"bind":bind,"units":units})
					fixed_total += units
			var hand: Array = []
			var hand_total := 0.0
			for influence: Dictionary in row["weights"]:
				var name := String(influence["bone"])
				var value := float(influence["weight"])
				if name.begins_with(prefix) and value > 0.0:
					hand.append({"bind":int(bind_lookup[name]),"weight":value})
					hand_total += value
			if hand_total <= 0.0 or fixed_total >= 65535 or fixed.size() + hand.size() > width:
				return _failure(report, ["Requested hand distribution cannot preserve existing native non-hand influences within the skin width"])
			hand.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["weight"]) > float(b["weight"]))
			var budget := 65535 - fixed_total
			var distributed := 0
			for influence: Dictionary in hand:
				influence["exact"] = float(budget) * float(influence["weight"]) / hand_total
				influence["units"] = roundi(influence["exact"])
				distributed += int(influence["units"])
			hand[0]["units"] = int(hand[0]["units"]) + budget - distributed
			var replacement: Array = fixed + hand
			for slot in width:
				skin.encode_u16(start + bones_offset + slot * 2, 0)
				skin.encode_u16(start + weights_offset + slot * 2, 0)
			var final_by_name := {}
			for slot in replacement.size():
				var influence: Dictionary = replacement[slot]
				var bind := int(influence["bind"])
				var units := int(influence["units"])
				skin.encode_u16(start + bones_offset + slot * 2, bind)
				skin.encode_u16(start + weights_offset + slot * 2, units)
				final_by_name[bind_names[bind]] = float(units) / 65535.0
				if influence.has("exact"):
					report["maximum_weight_quantization_error"] = maxf(report["maximum_weight_quantization_error"], absf(float(units) - float(influence["exact"])) / 65535.0)
				if units > 0:
					var box: AABB = bounds[bind]
					if box.size.x < 0.0:
						bounds[bind] = AABB(positions[vertex], Vector3.ZERO)
					else:
						bounds[bind] = box.expand(positions[vertex])
			for influence: Dictionary in row["weights"]:
				var name := String(influence["bone"])
				report["maximum_source_requested_weight_difference"] = maxf(report["maximum_source_requested_weight_difference"], absf(float(influence["weight"]) - float(final_by_name.get(name, 0.0))))
			for influence: Dictionary in fixed:
				var bind := int(influence["bind"])
				var expected_units := int(influence["units"])
				var found_units := 0
				for slot in width:
					if skin.decode_u16(start + bones_offset + slot * 2) == bind:
						found_units += skin.decode_u16(start + weights_offset + slot * 2)
				if expected_units != found_units:
					return _failure(report, ["Native non-hand influence changed"])
			mapped_vertices += 1
			changed_eligible[vertex] = true
			if skin.slice(start, start + stride) != original_skin.slice(start, start + stride):
				changed_vertices += 1
		for vertex in positions.size():
			if not changed_eligible.has(vertex):
				var start := vertex * stride
				if skin.slice(start, start + stride) != original_skin.slice(start, start + stride):
					return _failure(report, ["An unpatched native skin record changed"])
		stored_surface["skin_data"] = skin
		stored_surface["bone_aabbs"] = bounds
		stored_surface.erase("material")
		storage[surface] = stored_surface
		report["mapped_runtime_vertices"] += mapped_vertices
		report["changed_runtime_vertices"] += changed_vertices
		report["surfaces"].append({"surface":surface,"vertices":positions.size(),"mapped_vertices":mapped_vertices,
			"changed_vertices":changed_vertices,"skin_width":width,"native_format":format,
			"source_skin_sha256":_hash(original_skin),"variant_skin_sha256":_hash(skin),
			"vertex_bytes":native_surface.get("vertex_data", PackedByteArray()).size(),
			"attribute_bytes":native_surface.get("attribute_data", PackedByteArray()).size(),
			"index_bytes":native_surface.get("index_data", PackedByteArray()).size(),
			"blend_shape_bytes":native_surface.get("blend_shape_data", PackedByteArray()).size()})
	if mapped.size() != rows.size():
		var missing: Array = []
		for index in rows.size():
			if not mapped.has(index): missing.append(rows[index]["vertex"])
		return _failure(report, ["Unmapped authored hand vertices: " + str(missing)])
	var variant := ArrayMesh.new()
	variant.resource_name = source.resource_name + ".PX9.HandSkin"
	for index in source.get_blend_shape_count():
		variant.add_blend_shape(source.get_blend_shape_name(index))
	variant.blend_shape_mode = source.blend_shape_mode
	variant.custom_aabb = source.custom_aabb
	variant.lightmap_size_hint = source.lightmap_size_hint
	for key in source.get_meta_list():
		variant.set_meta(key, source.get_meta(key))
	variant.set("_surfaces", storage)
	report["mapped_source_rows"] = mapped.size()
	report["runtime_blend_shapes"] = variant.get_blend_shape_count()
	report["runtime_surfaces"] = variant.get_surface_count()
	report["raw_geometry_and_morph_buffers_byte_identical"] = compare_geometry_buffers(source, variant)
	if not report["raw_geometry_and_morph_buffers_byte_identical"]:
		return _failure(report, ["Native geometry or morph buffers changed while applying the skin patch"])
	report["passed"] = true
	report["errors"] = errors
	return {"mesh":variant,"report":report}

static func compare_geometry_buffers(source: ArrayMesh, variant: ArrayMesh) -> bool:
	if source.get_surface_count() != variant.get_surface_count() or source.get_blend_shape_count() != variant.get_blend_shape_count() or source.blend_shape_mode != variant.blend_shape_mode:
		return false
	for index in source.get_blend_shape_count():
		if source.get_blend_shape_name(index) != variant.get_blend_shape_name(index): return false
	for surface in source.get_surface_count():
		var a := RenderingServer.mesh_get_surface(source.get_rid(), surface)
		var b := RenderingServer.mesh_get_surface(variant.get_rid(), surface)
		for key in RAW_GEOMETRY_KEYS + ["primitive", "format", "vertex_count", "index_count", "aabb", "uv_scale"]:
			if a.get(key) != b.get(key): return false
	return true

static func _match_rows(point: Vector3, points: PackedVector3Array, grid: Dictionary) -> Array:
	var candidates: Array = grid.get(Vector3i((point * 100000.0).round()), [])
	var best := INF
	var found: Array = []
	if candidates.is_empty():
		for index in points.size():
			if point.distance_squared_to(points[index]) <= POSITION_TOLERANCE * POSITION_TOLERANCE:
				candidates.append(index)
	for index in candidates:
		var distance := point.distance_squared_to(points[index])
		if distance > POSITION_TOLERANCE * POSITION_TOLERANCE:
			continue
		if distance < best - 0.00000000000001:
			best = distance
			found = [index]
		elif absf(distance - best) <= 0.00000000000001:
			found.append(index)
	return found

static func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

static func _failure(report: Dictionary, messages: Array) -> Dictionary:
	report["passed"] = false
	report["errors"] = messages
	return {"mesh":null,"report":report}
