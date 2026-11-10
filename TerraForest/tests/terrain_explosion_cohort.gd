# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
	for generator in [1,31]:
		var control:RefCounted=ClassDB.instantiate("TerrainCore")
		var candidate:RefCounted=ClassDB.instantiate("TerrainCore")
		control.execute(Codec.command(6,[1703,generator]));candidate.execute(Codec.command(6,[1703,generator]))
		var height:float=control.execute(Codec.point_command(Vector3(1296,0,1296))).decode_float(12)
		var commands:Array[PackedByteArray]=[];var replies:Array[PackedByteArray]=[];var revisions:=PackedInt32Array()
		for z in 16:
			for x in 16:
				var p:=Vector3(1290+x*.75,height,1290+z*.75)
				commands.append(Codec.brush(p,p,3.5,0,false,0))
		for command:PackedByteArray in commands:
			replies.append(control.execute(command));revisions.append(control.execute(Codec.command(0)).decode_u32(12))
		var result:Dictionary=candidate.execute_explosion_cohort(commands)
		check(result.ok and result.completed==256 and result.replies==replies and result.revisions==revisions,"all ordered receipts and revisions match serial execution "+str(generator))
		check(candidate.execute(Codec.command(4,[3]))==control.execute(Codec.command(4,[3])),"exact serialized terrain matches "+str(generator))
		candidate.configure_mesh_height_cache(true)
		var same_meshes:=true
		for z in [1280,1296]:
			for x in [1280,1296]:
				same_meshes=same_meshes and candidate.execute(Codec.command(1,[x,z,16,1]))==control.execute(Codec.command(1,[x,z,16,1]))
		check(same_meshes,"mesh positions normals materials lighting and collision faces match exactly "+str(generator))
		check(result.height_hits>0 and result.height_hits<result.height_requests,"bounded cache reuses exact generator values")
		var before:PackedByteArray=candidate.execute(Codec.command(4,[3]))
		var invalid:Array=commands.duplicate();invalid.append(commands[0])
		check(not candidate.execute_explosion_cohort(invalid).ok and candidate.execute(Codec.command(4,[3]))==before,"oversized cohort cannot mutate terrain")
		check(not candidate.execute_explosion_cohort([Codec.command(6,[44,1])]).ok and candidate.execute(Codec.command(4,[3]))==before,"generator mutations are rejected before cache scope")
		var bad:PackedByteArray=commands[0].duplicate();bad.encode_float(28,NAN)
		var failure:Dictionary=candidate.execute_explosion_cohort([commands[0],bad,commands[1]])
		check(not failure.ok and failure.completed==1 and failure.processed==2 and failure.revisions[0]==failure.revisions[1],"failure reports successful prefix and does not execute suffix")
		candidate.execute(Codec.command(6,[1704,generator]));control.execute(Codec.command(6,[1704,generator]))
		check(candidate.execute(commands[0])==control.execute(commands[0]),"subsequent reset and ordinary edits cannot reuse stale cache")
		var segment:=Codec.brush(Vector3(1291,height,1291),Vector3(1295,height+1,1293),2.5,0,false,0)
		check(candidate.execute_explosion_cohort([segment]).replies[0]==control.execute(segment),"non-point capsules retain original distance evaluation")
		var distant:Array[PackedByteArray]=[];var distant_replies:Array[PackedByteArray]=[]
		for x in [1,33,65,1999]:
			var p:=Vector3(x,0,x);p.y=control.execute(Codec.point_command(p)).decode_float(12)
			distant.append(Codec.brush(p,p,2.5,0,false,0))
		for command:PackedByteArray in distant:distant_replies.append(control.execute(command))
		check(candidate.execute_explosion_cohort(distant).replies==distant_replies and candidate.execute(Codec.command(4,[3]))==control.execute(Codec.command(4,[3])),"cache collisions and world boundaries retain exact fields and receipts")
		check(candidate.execute(Codec.command(1,[0,0,16,1]))==control.execute(Codec.command(1,[0,0,16,1])),"boundary mesh retains uncached exterior height semantics")
	print("TERRAIN_EXPLOSION_COHORT failures=",failures);quit(1 if failures else 0)
