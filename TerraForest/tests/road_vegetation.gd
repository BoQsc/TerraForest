# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
class TerrainStub extends Node3D:
	var epoch:=1
	var published_revision:=1
	var pending_edit:=false
	var world_ready:=true
func publish(ecosystem: Node,token: int,result: Dictionary) -> void:
	var key:=Vector2i(12,20)
	ecosystem._requests[token]={"key":key,"ids":PackedInt64Array([1,2]),"rotations":PackedFloat32Array([0,0]),"scales":PackedFloat32Array([1,1])}
	ecosystem._pending_cells[key]=token
	ecosystem._surface_ready(token,result.points,result.normals,1,1)
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func sample(core: Object,points: PackedVector3Array) -> Dictionary:
	var packet:=Codec.command(17,[points.size()]);packet.append_array(points.to_byte_array())
	var reply: PackedByteArray=core.execute(packet)
	if not Codec.reply_ok(reply) or reply.size()!=16+points.size()*24: return {}
	return {"points":Codec._packed_channel(reply,16,points.size(),12,TYPE_PACKED_VECTOR3_ARRAY),"normals":Codec._packed_channel(reply,16+points.size()*12,points.size(),12,TYPE_PACKED_VECTOR3_ARRAY)}
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,2]))
	var points:=PackedVector3Array([Vector3(800.25,0,1310.25),Vector3(812.25,0,1310.25)])
	var before:=sample(core,points)
	check(not before.is_empty() and before.normals[0].y>0 and before.normals[1].y>0,"natural roots supported before paving")
	if before.is_empty(): quit(1);return
	var center: Vector3=before.points[0]
	var a:=center-Vector3(2,0,0);var b:=center+Vector3(2,0,0)
	check(Codec.reply_ok(core.execute(Codec.graded_bed(a,b,2,8,12,4))),"native asphalt edit accepted")
	var paved:=sample(core,points)
	check(not paved.is_empty() and paved.normals[0]==Vector3.ZERO,"asphalt root rejected even at unchanged natural surface height")
	check(not paved.is_empty() and paved.points[1]==before.points[1] and paved.normals[1]==before.normals[1],"neighbor in same 64 m owner retains exact support")
	check(Codec.reply_ok(core.execute(Codec.graded_bed(a,b,2,8,12,1))),"same road geometry repainted stone")
	var stone:=sample(core,points)
	check(not stone.is_empty() and stone.normals[0].y>0,"identical stone geometry allows root support again")
	check(not stone.is_empty() and stone.normals[1]==before.normals[1],"neighbor remains unchanged after repaint")
	var vegetation=load("res://addons/vegetation/vegetation_world.gd").new();root.add_child(vegetation)
	check(vegetation.enable_trunk_collision() and vegetation.initialize()==OK,"vegetation renderer and trunk collision initialize")
	var terrain:=TerrainStub.new()
	var ecosystem=load("res://addons/world_ecosystem/world_ecosystem.gd").new()
	ecosystem.terrain=terrain;ecosystem.vegetation=vegetation;ecosystem._wanted[Vector2i(12,20)]=true
	publish(ecosystem,1,before)
	check(vegetation.renderer.roots.size()==2 and vegetation.trunk_collision.get_ids().size()==2,"natural samples publish both roots and trunks")
	vegetation.renderer.roots[2].time=123.0
	publish(ecosystem,2,paved)
	check(not vegetation.renderer.roots.has(1) and not vegetation.trunk_collision.get_ids().has(1),"asphalt resampling retires only paved root and trunk")
	check(vegetation.renderer.roots.has(2) and vegetation.renderer.roots[2].time==123.0 and vegetation.trunk_collision.get_ids().has(2),"same-owner neighbor retains renderer transition and trunk")
	publish(ecosystem,3,stone)
	check(vegetation.renderer.roots.has(1) and vegetation.trunk_collision.get_ids().has(1),"stone repaint restores supported root and trunk")
	ecosystem.free();terrain.free();vegetation.free()
	quit(0 if failures==0 else 1)
