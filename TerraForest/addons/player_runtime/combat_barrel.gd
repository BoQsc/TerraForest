# SPDX-License-Identifier: 0BSD
extends RefCounted
const KEY:="combat/explosive_barrel/v1"
const ITEM:=222
const BOUNDS:=AABB(Vector3(-.36,0,-.36),Vector3(.72,1.05,.72))

# Fast chains consume barrels before the terrain worker is free. The world
# snapshot keeps each outstanding crater with the already-consumed barrel ID.
class CraterQueue extends RefCounted:
	const LIMIT:=256
	const RECORD_BYTES:=20
	var pending:Array[Dictionary]=[]
	var ticket:=-1

	func capture_snapshot()->PackedByteArray:
		var bytes:=PackedByteArray()
		bytes.resize(pending.size()*RECORD_BYTES)
		for index in pending.size():
			var offset:=index*RECORD_BYTES
			bytes.encode_s64(offset,pending[index].id)
			var point:Vector3=pending[index].point
			for axis in 3:bytes.encode_float(offset+8+4*axis,point[axis])
		return bytes

	func validate_snapshot(bytes:PackedByteArray)->bool:
		if bytes.size()>LIMIT*RECORD_BYTES or bytes.size()%RECORD_BYTES!=0:return false
		for offset in range(0,bytes.size(),RECORD_BYTES):
			if bytes.decode_s64(offset)<=0:return false
			for axis in 3:
				if not is_finite(bytes.decode_float(offset+8+4*axis)):return false
		return true

	func restore_snapshot(bytes:PackedByteArray)->bool:
		if not validate_snapshot(bytes):return false
		pending.clear()
		ticket=-1
		for offset in range(0,bytes.size(),RECORD_BYTES):
			var point:=Vector3(bytes.decode_float(offset+8),bytes.decode_float(offset+12),bytes.decode_float(offset+16))
			pending.append({"id":bytes.decode_s64(offset),"point":point})
		return true

static func mesh()->ArrayMesh:
	var result:=ArrayMesh.new()
	for band in 5:
		var cylinder:=CylinderMesh.new();cylinder.radial_segments=24;cylinder.rings=1
		cylinder.top_radius=.36 if band in [1,3] else .34;cylinder.bottom_radius=cylinder.top_radius
		cylinder.height=.055 if band in [1,3] else (.08 if band==4 else .46)
		var material:=StandardMaterial3D.new();material.albedo_color=Color("d6ad42") if band==2 else Color("353d43") if band in [1,3] else Color("9a3229");material.roughness=.64;material.metallic=.5
		var arrays:=cylinder.get_mesh_arrays();var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var y:float=[.23,.28,.70,.78,1.01][band]
		for index in vertices.size():vertices[index].y+=y
		arrays[Mesh.ARRAY_VERTEX]=vertices;result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.surface_set_material(band,material)
	return result
static func register(world:Node)->Node3D:
	var collection:Node3D=world.register_model(KEY,mesh())
	if collection==null or not collection.configure_collision(BOUNDS,96,256,8):return null
	return collection
