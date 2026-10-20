# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var core: RefCounted
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func query(command: int,points: PackedVector3Array,revision: int=0) -> PackedByteArray:
	var packet:=Codec.command(command,[revision,points.size()]);packet.append_array(points.to_byte_array());return core.execute(packet)
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	core=ClassDB.instantiate("TerrainCore")
	var points:=PackedVector3Array()
	for i in 64:points.append(Vector3(794.125+(i%8)*1.37,0,1306.235+(i/8)*1.29))
	var packet:=Codec.command(17,[points.size()]);packet.append_array(points.to_byte_array())
	var surface: PackedByteArray=core.execute(packet)
	check(Codec.reply_ok(surface),"native surface sampler available")
	if not Codec.reply_ok(surface):quit(1);return
	var probes:=PackedVector3Array();var accepted:=0
	for i in 64:
		var normal:=Vector3(surface.decode_float(16+64*12+i*12),surface.decode_float(20+64*12+i*12),surface.decode_float(24+64*12+i*12))
		if normal.y<0.82:continue
		var point:=Vector3(surface.decode_float(16+i*12),surface.decode_float(20+i*12),surface.decode_float(24+i*12))
		probes.append(point-Vector3.UP*0.35);probes.append(point+Vector3.UP*0.35);accepted+=1
	var old: PackedByteArray=query(29,probes);var reply: PackedByteArray=query(31,probes)
	check(accepted>=48 and Codec.reply_ok(reply) and reply.size()==20+probes.size()*4,"bounded interpolated support query returns every sample")
	if not Codec.reply_ok(reply):quit(1);return
	var mismatch:=0;var valid:=true;var max_error:=0.0
	for i in accepted:
		valid=valid and reply.decode_float(20+i*8)<0 and reply.decode_float(24+i*8)>0
		if old.decode_float(20+i*8)>=0 or old.decode_float(24+i*8)<0:mismatch+=1
	check(valid,"every accepted natural surface also passes authored interpolated support")
	check(mismatch>0,"fixture exposes floor-rounded support rejection")
	# Independent weighted sum of the legacy integer lattice query.
	for i in probes.size():
		var point: Vector3=probes[i];var base:=point.floor();var delta:=point-base
		var corners:=PackedVector3Array()
		for k in 8:corners.append(base+Vector3(k&1,(k>>1)&1,(k>>2)&1))
		var samples: PackedByteArray=query(29,corners);var expected:=0.0
		for k in 8:expected+=samples.decode_float(20+k*4)*(delta.x if k&1 else 1-delta.x)*(delta.y if k&2 else 1-delta.y)*(delta.z if k&4 else 1-delta.z)
		max_error=maxf(max_error,absf(expected-reply.decode_float(20+i*4)))
	check(max_error<0.00001,"interpolated values match independently weighted lattice corners")
	check(not Codec.reply_ok(query(31,probes,1)),"stale revision rejected")
	check(not Codec.reply_ok(query(31,PackedVector3Array())),"empty query rejected")
	check(not Codec.reply_ok(query(31,PackedVector3Array([Vector3(NAN,1,1)]))),"nonfinite coordinate rejected")
	var large:=PackedVector3Array();large.resize(513);large.fill(Vector3(800,10,1312))
	check(not Codec.reply_ok(query(31,large)),"oversize query rejected")
	var integer:=PackedVector3Array([Vector3(800,40,1312),Vector3(801,41,1313)])
	check(query(31,integer).slice(12)==query(29,integer).slice(12),"integer queries retain existing payload values and layout")
	# Shallow grading must return the edited root, not just accept its old height.
	core.execute(Codec.command(6,[42,17]))
	var root_query:=Codec.command(17,[1])
	root_query.append_array(PackedVector3Array([Vector3(906.25,0,855.25)]).to_byte_array())
	var initial:PackedByteArray=core.execute(root_query)
	var root_point:=Vector3(initial.decode_float(16),initial.decode_float(20),initial.decode_float(24))
	check(initial.decode_float(32)>0.82,"shallow grading fixture has supported ground")
	var grade:=root_point.y-0.2
	var a:=Vector3(root_point.x-3,grade,root_point.z)
	var b:=Vector3(root_point.x+3,grade,root_point.z)
	check(Codec.reply_ok(core.execute(Codec.graded_bed(a,b,2,3,4,1))),"shallow road shoulder cut accepted")
	var cut:PackedByteArray=core.execute(root_query)
	var cut_point:=Vector3(cut.decode_float(16),cut.decode_float(20),cut.decode_float(24))
	var residual:PackedByteArray=query(31,PackedVector3Array([cut_point]),1)
	check(cut.decode_float(32)>0.82 and absf(residual.decode_float(20))<0.002 and cut_point.y<root_point.y-0.1,"accepted root follows edited zero surface rather than original height")
	var saved:PackedByteArray=core.execute(Codec.command(4)).slice(12)
	var fresh=ClassDB.instantiate("TerrainCore")
	var restore:=Codec.command(5);restore.append_array(saved)
	check(Codec.reply_ok(fresh.execute(restore)) and fresh.execute(root_query)==cut,"edited root placement survives native save/reload exactly")
	core.execute(Codec.brush(cut_point,cut_point,1.5,0,false,1))
	check(core.execute(root_query).decode_float(32)==0.0,"deeper mining rejects root instead of relocating vegetation into excavation")
	core=null
	var result:={"checks":checks,"failures":failures,"accepted":accepted,"legacy_rejections":mismatch,"max_error":max_error}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/ground_support_surface.json",FileAccess.WRITE);file.store_string(JSON.stringify(result));file.close()
	print("GROUND_SUPPORT_SURFACE ",JSON.stringify(result))
	quit(1 if failures else 0)
