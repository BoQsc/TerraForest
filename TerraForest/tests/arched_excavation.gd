# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var checks:=0
var failures:=0
var core:RefCounted
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func packet(start:Vector3,finish:Vector3,width:float,height:float,profile:int=12)->PackedByteArray:
	var bytes:=Codec.graded_bed(start,finish,width,1,height,1);bytes.resize(52);bytes.encode_u32(48,profile)
	return bytes
func density(point:Vector3)->float:
	var query:=Codec.command(7);query.resize(16)
	query.encode_float(4,point.x);query.encode_float(8,point.y);query.encode_float(12,point.z)
	return core.execute(query).decode_float(16)
func run()->void:
	if not ClassDB.class_exists("TerrainCore"):GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	core=ClassDB.instantiate("TerrainCore")
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,5]))),"isolated material-field fixture initializes")
	check(Codec.reply_ok(core.execute(Codec.brush(Vector3(100,50,100),Vector3(100,50,100),18,1,true,1))),"bounded solid rock fixture")
	var original:PackedByteArray=core.execute(Codec.command(4))
	var shape:=packet(Vector3(88,45,100),Vector3(112,45,100),3,4.5)
	var result:PackedByteArray=core.execute(shape)
	check(Codec.reply_ok(result) and result.decode_u32(16)>0,"native arched cut changes the existing density field")
	check(density(Vector3(100,46,100))>0 and density(Vector3(100,49,100))>0,"walkable center and arched headroom are open")
	check(density(Vector3(100,44,100))<0 and density(Vector3(100,45,100))==0,"floor stays on its exact authored level")
	check(density(Vector3(100,50,100))<0 and density(Vector3(100,48,104))<0,"roof and side walls retain actual solid rock")
	check(density(Vector3(100,46,102))>0 and density(Vector3(100,49,102))<0,"rounded roof is not a rectangular tunnel")
	var saved:PackedByteArray=core.execute(Codec.command(4));var restore:=Codec.command(5);restore.append_array(saved.slice(12))
	check(Codec.reply_ok(core.execute(restore)) and core.execute(Codec.command(4))==saved,"density and material save/reload remain byte-exact")
	check(Codec.reply_ok(core.execute(shape)) and core.execute(Codec.command(4))==saved,"repeating the same excavation is a no-op")
	for flags in [8,9,10,11,13,14,15]:
		check(not Codec.reply_ok(core.execute(packet(Vector3(88,45,100),Vector3(112,45,100),3,4.5,flags))) and core.execute(Codec.command(4))==saved,"unsupported arched profile rejects atomically: "+str(flags))
	for dimensions in [Vector2(1,2),Vector2(3,2.9),Vector2(3,5.5),Vector2(NAN,4.5),Vector2(3,INF)]:
		check(not Codec.reply_ok(core.execute(packet(Vector3(88,45,100),Vector3(112,45,100),dimensions.x,dimensions.y))) and core.execute(Codec.command(4))==saved,"invalid arch dimensions reject atomically")
	var shoulder:=shape.duplicate();shoulder.encode_float(44,1)
	check(not Codec.reply_ok(core.execute(shoulder)) and core.execute(Codec.command(4))==saved,"arched cuts reject unsupported shoulders atomically")
	restore=Codec.command(5);restore.append_array(original.slice(12));core.execute(restore)
	var ramp:=packet(Vector3(88,44,100),Vector3(112,48,100),3,4.5)
	check(Codec.reply_ok(core.execute(ramp)) and density(Vector3(94,46,100))>0 and density(Vector3(106,48,100))>0,"sloped passage has continuous rising floor")
	check(density(Vector3(94,44,100))<0 and density(Vector3(106,46,100))<0,"sloped passage preserves support below both stations")
	restore=Codec.command(5);restore.append_array(original.slice(12));core.execute(restore)
	core.execute(Codec.command(3,[100,44,100,1]));core.execute(Codec.command(3,[100,46,100,1]))
	var exact:PackedByteArray=core.execute(shape)
	check(Codec.reply_ok(exact) and exact.decode_u32(24)==1,"arched cut removes interior voxel cube but preserves cube beneath flat floor")
	print("ARCHED_EXCAVATION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
