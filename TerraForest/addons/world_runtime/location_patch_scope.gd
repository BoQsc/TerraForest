# SPDX-License-Identifier: 0BSD
extends RefCounted

static func integers(bytes: PackedByteArray, offset: int) -> Vector3i:
	return Vector3i(bytes.decode_s32(offset), bytes.decode_s32(offset + 4), bytes.decode_s32(offset + 8))

static func vector(bytes: PackedByteArray, offset: int) -> Vector3:
	return Vector3(bytes.decode_float(offset), bytes.decode_float(offset + 4), bytes.decode_float(offset + 8))

static func identities(bytes: PackedByteArray, offset: int, count: int, stride: int) -> PackedInt64Array:
	var result := PackedInt64Array()
	result.resize(count)
	for index in count:
		result[index] = bytes.decode_s64(offset + index * stride)
	return result

static func normalized_arguments(kind: String, arguments: Array) -> Array:
	var result: Array = arguments.duplicate(true)
	if kind == "corpse":
		if result[0].size() != result[1].size():
			return []
		var pairs: Dictionary = {}
		for index in result[0].size():
			if pairs.has(result[0][index]):
				return []
			pairs[result[0][index]] = result[1][index]
		var ids: PackedInt64Array = result[0].duplicate()
		ids.sort()
		var anchors := PackedInt64Array()
		for identity in ids:
			anchors.append(pairs[identity])
		return [ids, anchors]
	for index in result.size():
		if result[index] is PackedInt64Array or result[index] is PackedStringArray:
			var values: Variant = result[index].duplicate()
			values.sort()
			for position in range(1, values.size()):
				if values[position] == values[position - 1]:
					return []
			result[index] = values
	return result

static func describe(owner: Object, kind: String, bytes: PackedByteArray) -> Dictionary:
	if not kind in ["field", "cube", "cell", "placement", "door", "container", "resident", "corpse", "harvest", "ground", "water", "damage"]:
		return {}
	if bytes.size() < 8 or bytes.size() > 16 * 1024 * 1024 or bytes.decode_u32(4) != 1:
		return {}
	if kind == "placement":
		var members: Dictionary = owner.placement_patch_members(bytes)
		if not members.get("ok", false):
			return {}
		return {"arguments": [Vector3i(members.bounds.position), Vector3i(members.bounds.size)], "signature": bytes.slice(36, 68), "ids": members.ids, "asset": members.asset}
	if not owner.call("validate_" + kind + "_patch", bytes):
		return {}
	match kind:
		"field", "cube":
			return {"arguments": [integers(bytes, 16), integers(bytes, 28)], "signature": bytes.slice(0, 44)}
		"cell":
			return {"arguments": [integers(bytes, 8), integers(bytes, 20)], "signature": bytes.slice(0, 36)}
		"water":
			return {"arguments": [integers(bytes, 16), integers(bytes, 28)], "signature": bytes.slice(0, 12)}
		"door", "container", "resident", "harvest":
			var header: int = {"door": 88, "container": 24, "resident": 32, "harvest": 16}[kind]
			var stride: int = {"door": 120, "container": 544, "resident": 148, "harvest": 16}[kind]
			var count := bytes.decode_u32(12 if kind == "resident" else 8)
			var selected := identities(bytes, header, count, stride)
			var result := {"arguments": [selected], "signature": bytes.slice(0, header), "ids": selected}
			if kind == "resident":
				result.anchors = identities(bytes, header + 140, count, stride)
			return result
		"corpse":
			var selected := identities(bytes, 24, bytes.decode_u32(8), 1288)
			var anchors := identities(bytes, 32, bytes.decode_u32(8), 1288)
			return {"arguments": [selected, anchors], "signature": bytes.slice(0, 24)}
		"ground":
			var natural := identities(bytes, 64, bytes.decode_u32(48), 16)
			return {"arguments": [AABB(vector(bytes, 24), vector(bytes, 36)), natural], "signature": bytes.slice(0, 48), "plants": identities(bytes, 64 + natural.size() * 16, bytes.decode_u32(52), 64)}
		"damage":
			var keys := PackedStringArray()
			var offset := 16
			for index in bytes.decode_u32(8):
				var length := bytes.decode_u32(offset)
				keys.append(bytes.slice(offset + 12, offset + 12 + length).get_string_from_ascii())
				offset += 12 + length
			return {"arguments": [keys], "signature": bytes.slice(0, 16)}
	return {}
