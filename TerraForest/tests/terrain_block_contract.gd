# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Check=preload("res://addons/structures/foundation_check.gd")
const Contact=preload("res://addons/structures/terrain_contact.gd")
const Works=preload("res://addons/world_runtime/generation_earthworks.gd")
const Plan=preload("res://addons/structures/site_plan.gd")
var checks:=0
var failures:=0

# Test transport only. The production foundation state machine consumes actual
# native density replies, with the same paging/revision/interpolation contract.
class Field extends Node:
	var core:RefCounted
	var validator:RefCounted
	var world_ready:=true
	var pending_edit:=false
	var stopping:=false
	var epoch:=1
	var density_revision:=0
	func request_density_scan(points:PackedVector3Array,token:int,depth:int,interpolated:bool)->bool:
		var values:=PackedFloat32Array()
		for offset in range(0,points.size(),512):
			var batch:=points.slice(offset,offset+512)
			var query:=Codec.command(30 if depth else 31 if interpolated else 29,[density_revision,batch.size(),depth] if depth else [density_revision,batch.size()])
			query.append_array(batch.to_byte_array())
			var reply:PackedByteArray=core.execute(query)
			if not Codec.reply_ok(reply):return false
			for i in batch.size():values.append(reply.decode_float(20+i*4))
		validator.call_deferred("receive",{"token":token,"status":"ok","epoch":epoch,"revision":density_revision,"values":values})
		return true

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
	asset.configure(PackedInt32Array([0,0,0,1]));asset.set_meta("site_surface_offset",1);asset.set_meta("site_sample_band",1)
	check(Contact.describe(asset).ok and Contact.inset(asset)==.125,"one explicit soil datum for every at-grade building")
	var invalid:Resource=asset.duplicate();invalid.set_meta("site_sample_band",0)
	check(not Contact.describe(invalid).ok,"contradictory surface/sample metadata is rejected")
	invalid=asset.duplicate();invalid.set_meta("site_surface_inset",0.0)
	check(not Contact.describe(invalid).ok,"individual recipes cannot disable the required reveal")
	var floating:Resource=ClassDB.instantiate("NativeBlockPrefab")
	floating.configure(PackedInt32Array([0,3,0,1]));floating.configure_attachment_envelope(AABB(Vector3.ZERO,Vector3(1,5,1)))
	check(not Plan.foundation(floating,Vector3i(900,0,900),0,48).ok,"attachment envelope cannot stand in for an actual grounded block footprint")
	check(asset.clearance_sample_count()==0 and asset.terrain_surface_sample_count(1)==9,"single-cell apron omitted by old room scan has nine surface probes")
	var original:PackedVector3Array=asset.terrain_surface_samples(Vector3i.ZERO,0,0,512,1)
	for rotation in 4:
		var rotated:PackedVector3Array=asset.terrain_surface_samples(Vector3i(500,47,500),rotation,0,512,1)
		var agrees:=rotated.size()==original.size()
		for i in original.size():
			var point:=original[i]
			for turn in rotation:point=Vector3(1-point.z,point.y,point.x)
			agrees=agrees and rotated[i].is_equal_approx(point+Vector3(500,47,500))
		check(agrees,"surface samples follow exact native cell transform / turn "+str(rotation))
	var all_shapes:=true
	for shape in range(1,19):
		for rotation in (24 if shape>8 else 4):
			var word:=32768|((shape-9)<<8)|rotation if shape>8 else (128 if shape==8 else shape)|(rotation<<3)
			var fixture:Resource=ClassDB.instantiate("NativeBlockPrefab");fixture.configure(PackedInt32Array([0,0,0,word]))
			var samples:PackedVector3Array=fixture.terrain_surface_samples(Vector3i.ZERO,0,0,512,0)
			all_shapes=all_shapes and not samples.is_empty()
			for point in samples:all_shapes=all_shapes and point.is_finite() and point.y>=-.021 and point.y<1 and point.x>=0 and point.x<=1 and point.z>=0 and point.z<=1
	check(all_shapes,"all 18 shapes and all native mount orientations supply bounded surface probes")
	var stacked:Resource=ClassDB.instantiate("NativeBlockPrefab");stacked.configure(PackedInt32Array([0,0,0,1,0,1,0,1]))
	check(stacked.terrain_surface_sample_count(0)==0 and stacked.terrain_surface_sample_count(1)==9,"buried wall joins are excluded; exposed top remains checked")
	check(stacked.terrain_surface_samples(Vector3i.ZERO,4,0,512,0).is_empty() and stacked.terrain_surface_sample_count(4096)==-1,"invalid placement/band cannot produce accepted probes")
	stacked.configure(PackedInt32Array([0,0,0,2]))
	check(is_equal_approx(stacked.terrain_surface_samples(Vector3i.ZERO,0,0,1,0)[0].y,.48),"shape edits invalidate cached probes and preserve actual half-slab height")
	for soil_height in [48.0,47.75]:
		var field:=Field.new();root.add_child(field);field.core=ClassDB.instantiate("TerrainCore")
		field.core.execute(Codec.command(6,[1703,2]))
		field.core.execute(Codec.graded_bed(Vector3(490,soil_height,500),Vector3(510,soil_height,500),12,8,12,1))
		field.density_revision=field.core.execute(Codec.command(0)).decode_u32(12)
		field.validator=Check.new()
		check(field.validator.begin(field,asset,Vector3i(500,47,500),0),"real native terrain admits a bounded foundation check")
		var deadline:=Time.get_ticks_msec()+10000
		while field.validator.status=="checking" and Time.get_ticks_msec()<deadline:
			field.validator.tick(field);await process_frame
		check(field.validator.status.begins_with("Terrain intersects") if soil_height==48 else field.validator.status=="supported","coplanar soil rejects / separated soil accepts: "+field.validator.status)
		field.free()
	var cut:Dictionary={"start":Vector3(500,46,500),"finish":Vector3(505,46,500),"half_width":1.0,"depth":1.0,"clearance":5.0,"shoulder":0.0,"material":1,"phase":"excavation"}
	var road:Dictionary=cut.duplicate();road.erase("phase");road.material=4;road.start.y=49;road.finish.y=49
	var packets:=Works.packets([cut,road])
	check(packets.size()==2 and packets[-1].decode_float(8)==46 and packets[0].decode_float(8)==49,"final excavation follows paving even when input/material order differs")
	cut.phase="unknown";check(Works.packets([cut]).is_empty(),"unknown earthworks phase fails closed")
	var stair:Resource=ClassDB.instantiate("NativeBlockPrefab");stair.configure(PackedInt32Array([0,0,0,3]))
	var mask:Dictionary=stair.terrain_surface_clearance(Vector3i(500,47,500),0,0)
	check(mask.get("ok",false) and not mask.segments.is_empty(),"actual stair geometry compiles a bounded floor-clearance mask")
	var carved:RefCounted=ClassDB.instantiate("TerrainCore");carved.execute(Codec.command(6,[1703,2]))
	carved.execute(Codec.graded_bed(Vector3(490,49,500),Vector3(510,49,500),12,8,12,1))
	carved.execute(Codec.brush(Vector3(500,46,500),Vector3(500,46,500),.6,0,false,1))
	for packet:PackedByteArray in Works.packets(mask.segments):check(Codec.reply_ok(carved.execute(packet)),"subtractive mask applies before publication")
	var rev:int=carved.execute(Codec.command(0)).decode_u32(12)
	var stair_points:PackedVector3Array=stair.terrain_surface_samples(Vector3i(500,47,500),0,0,512,0)
	var query:=Codec.command(31,[rev,stair_points.size()]);query.append_array(stair_points.to_byte_array())
	var samples:PackedByteArray=carved.execute(query);var clear:=Codec.reply_ok(samples)
	for i in stair_points.size():clear=clear and samples.decode_float(20+i*4)>=0
	check(clear,"narrow masks preserve vertical clearance at lattice corners and every stair tread")
	query=Codec.command(31,[rev,1]);query.append_array(PackedVector3Array([Vector3(500,46,500)]).to_byte_array())
	check(carved.execute(query).decode_float(20)>0,"surface clearance never refills an existing void below the floor")
	var before:PackedByteArray=carved.execute(Codec.command(4));var malformed:PackedByteArray=Works.packets(mask.segments)[0];malformed.encode_u32(48,8)
	check(not Codec.reply_ok(carved.execute(malformed)) and before==carved.execute(Codec.command(4)),"unknown native profile rejects without changing saved terrain")
	for profile in [0,2]:
		var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,2]))
		var packet:=Codec.graded_bed(Vector3(500,48,500),Vector3(500,46,510),2.5,8,12,1)
		if profile:packet.resize(52);packet.encode_u32(48,profile)
		check(Codec.reply_ok(core.execute(packet)),"native sloped bed accepted / end profile "+str(profile))
		var revision:int=core.execute(Codec.command(0)).decode_u32(12)
		var cap_query:=Codec.command(31,[revision,1]);cap_query.append_array(PackedVector3Array([Vector3(500,48.1,498)]).to_byte_array())
		var reply:PackedByteArray=core.execute(cap_query)
		check(Codec.reply_ok(reply) and (reply.decode_float(20)>0 if profile else reply.decode_float(20)<0),"approach caps stay level behind threshold; legacy road grade extension remains explicit")
		var archive:PackedByteArray=core.execute(Codec.command(4)).slice(12)
		var restored:RefCounted=ClassDB.instantiate("TerrainCore");restored.execute(Codec.command(6,[1703,2]))
		var restore:=Codec.command(5);restore.append_array(archive)
		check(Codec.reply_ok(restored.execute(restore)),"edited approach persists in the existing terrain format")
	print("TERRAIN_BLOCK_CONTRACT checks=",checks," failures=",failures);quit(1 if failures else 0)
