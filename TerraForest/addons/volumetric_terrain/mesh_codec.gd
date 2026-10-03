# SPDX-License-Identifier: 0BSD
extends RefCounted

const MESH_MAGIC: int = 0x324d5254
const REPLY_MAGIC: int = 0x32505254

static func command(number: int, integers: Array = []) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(4 + integers.size() * 4)
	result.encode_u32(0, number)
	for i in range(integers.size()):
		result.encode_u32(4 + i * 4, int(integers[i]))
	return result

static func brush(a: Vector3, b: Vector3, radius: float, shape: int, add: bool, material: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(44)
	result.encode_u32(0, 2)
	result.encode_float(4, a.x)
	result.encode_float(8, a.y)
	result.encode_float(12, a.z)
	result.encode_float(16, b.x)
	result.encode_float(20, b.y)
	result.encode_float(24, b.z)
	result.encode_float(28, radius)
	result.encode_u32(32, shape)
	result.encode_u32(36, 1 if add else 0)
	result.encode_u32(40, material)
	return result

static func road_bed(a: Vector3,b: Vector3,half_width: float,depth: float) -> PackedByteArray:
	var packet:=PackedByteArray();packet.resize(36);packet.encode_u32(0,28)
	for axis in 3:
		packet.encode_float(4+axis*4,a[axis]);packet.encode_float(16+axis*4,b[axis])
	packet.encode_float(28,half_width);packet.encode_float(32,depth)
	return packet

static func point_command(point: Vector3) -> PackedByteArray:
	var result := command(7, [0, 0, 0])
	result.encode_float(4, point.x)
	result.encode_float(8, point.y)
	result.encode_float(12, point.z)
	return result

static func reply_ok(reply: PackedByteArray) -> bool:
	return reply.size() >= 12 and reply.decode_u32(0) == REPLY_MAGIC and reply.decode_u32(8) == 0

static func density_ray_command(from: Vector3, to: Vector3, budget: int, epoch: int, with_normal: bool=false) -> PackedByteArray:
	var packet := command(24 if with_normal else 23,[0,0,0,0,0,0,budget,epoch])
	for axis in range(3):
		packet.encode_float(4+axis*4,from[axis])
		packet.encode_float(16+axis*4,to[axis])
	return packet

static func decode_density_ray(reply: PackedByteArray) -> Dictionary:
	if reply.size()<12 or reply.decode_u32(0)!=REPLY_MAGIC or reply.decode_u32(4) not in [23,24]:
		return {"status":"error","error":"Invalid density query envelope"}
	if reply.decode_u32(8)==4 and reply.size()==12:
		return {"status":"cancelled","cancelled":true}
	if not reply_ok(reply) or reply.size()!=(52 if reply.decode_u32(4)==24 else 40) or reply.decode_u32(16)>2:
		return {"status":"error","error":"Invalid density query reply"}
	var result := {"status":["hit","miss","work_limit"][reply.decode_u32(16)],"revision":reply.decode_u32(12),"cells":reply.decode_u32(20)}
	if result.status=="hit":
		var fraction := reply.decode_float(24)
		var position := Vector3(reply.decode_float(28),reply.decode_float(32),reply.decode_float(36))
		if not is_finite(fraction) or fraction<0 or fraction>1 or not position.is_finite():
			return {"status":"error","error":"Invalid density hit"}
		result["fraction"]=fraction;result["position"]=position
		if reply.decode_u32(4)==24:
			var normal:=Vector3(reply.decode_float(40),reply.decode_float(44),reply.decode_float(48))
			if not normal.is_finite(): return {"status":"error","error":"Invalid density normal"}
			result["normal"]=normal
	return result

static func _packed_channel(source: PackedByteArray, offset: int, count: int, stride: int, type: int) -> Variant:
	# Use Godot's native Variant decoder, NOT a per-vertex GDScript loop.
	# TYPE_* constants come from this running engine, avoiding stale numeric type tables.
	var data := PackedByteArray()
	data.resize(8)
	data.encode_u32(0, type)
	data.encode_u32(4, count)
	data.append_array(source.slice(offset, offset + count * stride))
	return bytes_to_var(data)

static func decode_mesh(source: PackedByteArray) -> Dictionary:
	if source.size() < 36 or source.decode_u32(0) != MESH_MAGIC or source.decode_u32(4) != 5:
		return {"error": "Invalid or outdated mesh-cache header"}
	var nv: int = source.decode_u32(24)
	var ni: int = source.decode_u32(28)
	var nf: int = source.decode_u32(32)
	if nv > 2000000 or ni > 12000000 or nf > ni or ni % 3 != 0:
		return {"error": "Mesh-cache count is out of bounds"}
	if source.size() != 36 + nv * 56 + ni * 4 + nf * 12:
		return {"error": "Truncated mesh-cache packet"}
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	var offset: int = 36
	arrays[Mesh.ARRAY_VERTEX] = _packed_channel(source, offset, nv, 12, TYPE_PACKED_VECTOR3_ARRAY)
	offset += nv * 12
	arrays[Mesh.ARRAY_NORMAL] = _packed_channel(source, offset, nv, 12, TYPE_PACKED_VECTOR3_ARRAY)
	offset += nv * 12
	arrays[Mesh.ARRAY_TEX_UV] = _packed_channel(source, offset, nv, 8, TYPE_PACKED_VECTOR2_ARRAY)
	offset += nv * 8
	arrays[Mesh.ARRAY_TEX_UV2] = _packed_channel(source, offset, nv, 8, TYPE_PACKED_VECTOR2_ARRAY)
	offset += nv * 8
	arrays[Mesh.ARRAY_COLOR] = _packed_channel(source, offset, nv, 16, TYPE_PACKED_COLOR_ARRAY)
	offset += nv * 16
	arrays[Mesh.ARRAY_INDEX] = _packed_channel(source, offset, ni, 4, TYPE_PACKED_INT32_ARRAY)
	offset += ni * 4
	var faces: PackedVector3Array = _packed_channel(source, offset, nf, 12, TYPE_PACKED_VECTOR3_ARRAY)
	if not arrays[Mesh.ARRAY_VERTEX] is PackedVector3Array or not arrays[Mesh.ARRAY_INDEX] is PackedInt32Array:
		return {"error": "Godot packed-array decoder rejected the mesh"}
	var cavity_visibility: bool = false
	var transmission: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for value: Vector2 in transmission:
		if value.x < 0.999:
			cavity_visibility = true
			break
	return {"cavity_visibility": cavity_visibility, "key": Vector3i(source.decode_u32(8), source.decode_u32(12), source.decode_u32(16)),
		"step": source.decode_u32(20), "arrays": arrays, "faces": faces,
		"triangles": ni / 3, "bytes": source.size()}

static func encode_decoded_mesh(mesh: Dictionary) -> PackedByteArray:
	# Inverse of decode_mesh, using native packed-array conversions. No per-vertex
	# script packing. Derived cache only; this is not the authoritative world save.
	var arrays: Array = mesh["arrays"]
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var faces: PackedVector3Array = mesh["faces"]
	var key: Vector3i = mesh["key"]
	var bytes := PackedByteArray()
	bytes.resize(36)
	for i: int in range(9):
		bytes.encode_u32(i * 4, int([MESH_MAGIC, 5, key.x, key.y, key.z, int(mesh.get("step", maxi(1, key.z / 32))), positions.size(), indices.size(), faces.size()][i]))
	bytes.append_array(positions.to_byte_array())
	bytes.append_array(normals.to_byte_array())
	bytes.append_array(uv.to_byte_array())
	bytes.append_array(uv2.to_byte_array())
	bytes.append_array(colors.to_byte_array())
	bytes.append_array(indices.to_byte_array())
	bytes.append_array(faces.to_byte_array())
	return bytes
