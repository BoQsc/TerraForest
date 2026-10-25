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
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,21]))),"steep mountain fixture initializes current coastal terrain")
	var mountain_query:=Codec.command(17,[1])
	mountain_query.append_array(PackedVector3Array([Vector3(386.25,0,250.25)]).to_byte_array())
	var mountain:PackedByteArray=core.execute(mountain_query)
	var hit_point:=Vector3(mountain.decode_float(16),mountain.decode_float(20),mountain.decode_float(24))
	var hit_normal:=Vector3(mountain.decode_float(28),mountain.decode_float(32),mountain.decode_float(36))
	var nearby:=PackedVector3Array()
	for depth in range(-3,4):
		for across in range(-3,4):nearby.append(hit_point+Vector3(across*.25,0,depth*.25))
	var nearby_query:=Codec.command(17,[nearby.size()]);nearby_query.append_array(nearby.to_byte_array())
	var before_mining:PackedByteArray=core.execute(nearby_query)
	var natural_snapshot:PackedByteArray=core.execute(Codec.command(4)).slice(12)
	var brush_center:=hit_point-hit_normal*.35
	check(hit_normal.y<.82 and Codec.reply_ok(core.execute(Codec.brush(brush_center,brush_center,.65,0,false,1))),"ordinary pickaxe brush cuts the originally bare steep mountainside")
	var after_mining:PackedByteArray=core.execute(nearby_query)
	var new_grass:=0;var new_trees:=0;var unsupported_roots:=0
	for index in nearby.size():
		var old_up:=before_mining.decode_float(20+nearby.size()*12+index*12)
		var new_up:=after_mining.decode_float(20+nearby.size()*12+index*12)
		if old_up<.82 and new_up>=.82:new_grass+=1
		if old_up<cos(deg_to_rad(32.0)) and new_up>=cos(deg_to_rad(32.0)):new_trees+=1
		if old_up>0 and new_up==0:unsupported_roots+=1
	check(new_grass==0,"mining cannot turn a previously bare slope into new grass or bushes")
	check(new_trees==0,"mining cannot newly admit trees across their original slope limit")
	check(unsupported_roots>0,"excavated roots still lose unsupported vegetation")
	var mined_snapshot:PackedByteArray=core.execute(Codec.command(4)).slice(12)
	var mined_clone=ClassDB.instantiate("TerrainCore")
	var mined_restore:=Codec.command(5);mined_restore.append_array(mined_snapshot)
	check(Codec.reply_ok(mined_clone.execute(mined_restore)) and mined_clone.execute(nearby_query)==after_mining,"steep-slope eligibility survives reload without resident vegetation history")
	var natural_restore:=Codec.command(5);natural_restore.append_array(natural_snapshot)
	check(Codec.reply_ok(core.execute(natural_restore)) and core.execute(nearby_query)==before_mining,"restoring original terrain restores the exact original support samples")
	var underground:=hit_point-Vector3.UP*16
	check(Codec.reply_ok(core.execute(Codec.brush(underground,underground,.65,0,false,1))) and core.execute(nearby_query).slice(16)==before_mining.slice(16),"deep mining preserves all original surface roots and slope eligibility")
	core=null
	var result:={"checks":checks,"failures":failures,"accepted":accepted,"legacy_rejections":mismatch,"max_error":max_error,"new_grass":new_grass,"new_trees":new_trees,"unsupported_roots":unsupported_roots}
	var output:="res://reports/ground_support_surface.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--support-output="):output=argument.trim_prefix("--support-output=")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(result));file.close()
	print("GROUND_SUPPORT_SURFACE ",JSON.stringify(result))
	quit(1 if failures else 0)
