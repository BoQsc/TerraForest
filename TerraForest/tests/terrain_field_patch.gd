# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var checks:=0
var failures:=0

func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	run.call_deferred()

func check(passed:bool,label:String)->void:
	checks+=1
	if not passed:failures+=1
	print(("PASS " if passed else "FAIL ")+label)

func capture(core:RefCounted,origin:Vector3i,size:Vector3i)->PackedByteArray:
	var state:Dictionary=core.field_patch_state()
	return core.capture_field_patch(origin,size,state.revision,state.epoch)

func restore(core:RefCounted,patch:PackedByteArray)->Dictionary:
	var state:Dictionary=core.field_patch_state()
	return core.restore_field_patch(patch,state.revision,state.epoch)

func check_render_upload(arrays:Array)->void:
	var expected:=ArrayMesh.new()
	expected.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
	var reference:Dictionary=expected.get("_surfaces")[0]
	var packed:Dictionary=ClassDB.class_call_static("NativeTerrainCollision","pack_terrain_surface",arrays)
	for field in ["vertex_data","attribute_data","index_data","primitive","format","vertex_count","index_count","aabb"]:
		check(packed.get(field)==reference.get(field),"worker upload matches engine surface "+field)
		if packed.get(field) is PackedByteArray and packed[field]!=reference[field]:
			var a:PackedByteArray=packed[field];var b:PackedByteArray=reference[field]
			for offset in mini(a.size(),b.size()):
				if a[offset]!=b[offset]:
					print("UPLOAD_BYTE_DIFFERENCE ",field," offset=",offset," candidate=",a[offset]," expected=",b[offset]," lengths=",a.size(),"/",b.size())
					break
		elif packed.get(field)!=reference.get(field):print("UPLOAD_FIELD_DIFFERENCE ",field," candidate=",packed.get(field)," expected=",reference.get(field))
	var restored:=ArrayMesh.new()
	restored.set("_surfaces",[packed])
	check(restored.get_surface_count()==1 and restored.surface_get_arrays(0)==expected.surface_get_arrays(0),"packed terrain restores every rendered channel")

func check_index_width(count:int)->void:
	var channels:Array=[];channels.resize(Mesh.ARRAY_MAX)
	var points:=PackedVector3Array();points.resize(count);points.fill(Vector3(2,0,4))
	points[0]=Vector3.ZERO;points[1]=Vector3.RIGHT
	var normals:=PackedVector3Array();normals.resize(count);normals.fill(Vector3.UP)
	var tex:=PackedVector2Array();tex.resize(count)
	var colors:=PackedColorArray();colors.resize(count);colors.fill(Color.WHITE)
	channels[Mesh.ARRAY_VERTEX]=points;channels[Mesh.ARRAY_NORMAL]=normals
	channels[Mesh.ARRAY_TEX_UV]=tex;channels[Mesh.ARRAY_TEX_UV2]=tex;channels[Mesh.ARRAY_COLOR]=colors
	channels[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,count-1])
	check_render_upload(channels)

func floor_piece(x:float,height:float)->ConcavePolygonShape3D:
	var shape:=ConcavePolygonShape3D.new()
	shape.backface_collision=true
	shape.set_faces(PackedVector3Array([Vector3(x-1,height,-1),Vector3(x+1,height,-1),Vector3(x,height,1)]))
	return shape

func check_collider_slots()->void:
	var terrain:=preload("res://addons/volumetric_terrain/terrain_world.gd").new()
	var node:=MeshInstance3D.new()
	root.add_child(node)
	var body:=StaticBody3D.new();node.add_child(body)
	var first:=CollisionShape3D.new();first.shape=floor_piece(0,2);body.add_child(first)
	var old:Array=[first.shape]
	var replacement:Array=[floor_piece(0,0),floor_piece(4,1)]
	var slot:={"colliders":body.get_children(),"old_shapes":old,"shapes":replacement,"old_mesh":null,"mesh":null,"applied":false}
	var entry:={"body":body,"node":node,"resident_swap":slot}
	for state:int in [1,0,2,0]:
		if state==2:slot.shapes=[]
		terrain._apply_resident_swap(entry,state!=0)
		await physics_frame
		await physics_frame
		var hits:Array=[]
		for x:float in [0.0,4.0]:
			hits.append(node.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x,4,0),Vector3(x,-2,0),1)))
		if state==1:check(not hits[0].is_empty() and absf(hits[0].position.y)<.001 and not hits[1].is_empty() and hits[1].collider==body,"growing a resident owner installs both floors on the original body")
		elif state==2:check(hits[0].is_empty() and hits[1].is_empty(),"empty revision releases all old support")
		else:check(not hits[0].is_empty() and absf(hits[0].position.y-2)<.001 and hits[1].is_empty(),"rollback restores original floor and clears extra slot")
	node.free();terrain.free()

func run()->void:
	if DisplayServer.get_name()!="headless":
		check_index_width(65536)
		check_index_width(65537)
	await check_collider_slots()
	var core:RefCounted=ClassDB.instantiate("TerrainCore")
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,5]))),"empty field initializes")
	var origin:=Vector3i(1274,58,1274);var size:=Vector3i(13,13,13)
	var baseline:=capture(core,origin,size)
	check(baseline.size()==48+13*13*13*3 and core.validate_field_patch(baseline),"bounded binary baseline validates")
	check(core.field_patch_state().revision==0,"baseline capture does not create an edit")
	var center:=Vector3(1280,64,1280)
	check(Codec.reply_ok(core.execute(Codec.brush(center,center,3,0,true,3))),"normal terrain edit succeeds")
	var edited:=capture(core,origin,size)
	check(edited!=baseline,"baseline differs from real player field edit")
	var outside:=Vector3(1266,64,1280)
	check(Codec.reply_ok(core.execute(Codec.brush(outside,outside,2,1,true,2))),"outside player edit succeeds")
	var outside_origin:=Vector3i(1263,61,1277);var outside_size:=Vector3i(6,6,6)
	var preserved:=capture(core,outside_origin,outside_size)
	var state:Dictionary=core.field_patch_state()
	check(not core.restore_field_patch(baseline,state.revision-1,state.epoch).ok,"stale mutation revision rejects")
	check(not core.restore_field_patch(baseline,state.revision,state.epoch-1).ok,"stale owner epoch rejects")
	check(core.capture_field_patch(origin,size,state.revision-1,state.epoch).is_empty(),"stale capture revision rejects")
	check(core.capture_field_patch(origin,size,state.revision,state.epoch-1).is_empty(),"stale capture epoch rejects")
	check(capture(core,origin,size)==edited,"rejected requests preserve current density and material")
	var old_key:Dictionary=core.geometry_cache_key(1264,1264,32,1)
	var old_mesh:PackedByteArray=core.execute(Codec.command(20,[1264,1264,32,1]))
	check(Codec.reply_ok(old_mesh),"edited terrain populates native geometry cache")
	var response:=restore(core,baseline)
	check(response.ok and response.changes>0 and response.minimum==Vector3(origin) and response.maximum==Vector3(origin+size-Vector3i.ONE),"local restore gives exact changed sample bounds")
	check(capture(core,origin,size)==baseline,"restored baseline matches captured lattice bytes")
	check(capture(core,outside_origin,outside_size)==preserved,"outside authored edit remains unchanged")
	check(core.geometry_cache_key(1264,1264,32,1).key!=old_key.key,"derived geometry identity changes after field restoration")
	var restored_mesh:PackedByteArray=core.execute(Codec.command(20,[1264,1264,32,1]))
	var reference_mesh:PackedByteArray=core.execute(Codec.command(1,[1264,1264,32,1]))
	check(Codec.reply_ok(restored_mesh) and Codec.reply_ok(reference_mesh) and restored_mesh.slice(12)==reference_mesh.slice(12) and restored_mesh!=old_mesh,"restored cached geometry matches fresh meshing and discards old surface")
	state=core.field_patch_state();response=restore(core,baseline)
	check(response.ok and response.changes==0 and core.field_patch_state()==state,"no-op restore does not dirty field")
	var corrupt:=edited.duplicate();corrupt[50]^=1
	check(not core.validate_field_patch(corrupt) and not restore(core,corrupt).ok,"damaged persistent baseline rejects")
	check(restore(core,edited).ok,"real edited samples can be restored too")
	var storage_path:=ProjectSettings.globalize_path("user://field_patch_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	var store:RefCounted=ClassDB.instantiate("NativeTerrainRegionStore")
	check(store.open_store(storage_path,true),"isolated persistent region store opens")
	var raw:PackedByteArray=core.execute(Codec.command(4,[3])).slice(12)
	var checkpoint:PackedByteArray=store.publish_snapshot(raw)
	check(checkpoint.size()==40,"real terrain checkpoint publishes")
	var mounted:RefCounted=ClassDB.instantiate("TerrainCore")
	check(mounted.mount_storage_checkpoint(storage_path,checkpoint,64),"fresh owner mounts deferred pages")
	check(capture(mounted,origin,size)==edited,"local capture resolves archived density and materials")
	check(restore(mounted,baseline).ok,"local reset operates on mounted storage")
	check(capture(mounted,outside_origin,outside_size)==preserved,"mounted reset preserves outside edits")
	var snapshot:RefCounted=mounted.capture_storage_snapshot()
	check(snapshot!=null and snapshot.stats().sample_bytes>0,"restored pages carry dirty storage versions")
	var next:PackedByteArray=store.publish_capture(snapshot,checkpoint)
	check(next.size()==40 and next!=checkpoint and mounted.commit_storage_snapshot(snapshot,next),"reset publishes and commits new durable checkpoint")
	var reopened:RefCounted=ClassDB.instantiate("TerrainCore")
	check(reopened.mount_storage_checkpoint(storage_path,next,64) and capture(reopened,origin,size)==baseline,"new checkpoint reopens exact reset state")
	check(capture(reopened,outside_origin,outside_size)==preserved,"fresh restore retains neighboring player changes")
	check(store.expand_snapshot(checkpoint)==raw,"original checkpoint remains immutable")
	state=core.field_patch_state()
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,5]))),"same-seed reset accepted")
	check(core.field_patch_state().epoch!=state.epoch and not core.restore_field_patch(edited,0,state.epoch).ok,"same revision after reset cannot reuse old epoch")
	check(Codec.reply_ok(core.execute(Codec.command(6,[42,5]))) and not restore(core,edited).ok,"different seed cannot accept captured baseline")
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,1]))) and not restore(core,edited).ok,"different generator cannot accept captured baseline")
	# Reconstruct a cut in a copied revision while the live authority advances.
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,31]))),"regional generator initializes for contact reconstruction")
	var point:=Vector3(1008,40,1008)
	check(Codec.reply_ok(core.execute(Codec.brush(point,point,2,0,true,2))),"contact fixture has authored density and material")
	state=core.field_patch_state()
	var bounds:=Rect2i(992,992,32,32)
	var build_epoch:int=core.execute(Codec.command(13)).decode_u32(12)
	var frozen:RefCounted=core.capture_contact_core(bounds,state.revision,build_epoch)
	check(frozen!=null and core.capture_contact_core(bounds,state.revision+1,build_epoch)==null,"only a matching contact revision can be captured")
	# Compare the shared density-cell surface against independent extraction.
	var owner:=Codec.command(20,[992,992,32,1,build_epoch])
	var canonical:PackedByteArray=core.execute(Codec.command(1,[992,992,32,1,build_epoch]))
	var shared_mesh:PackedByteArray=frozen.execute(owner)
	check(Codec.reply_ok(shared_mesh) and shared_mesh.slice(12)==canonical.slice(12),"resident cells reproduce the rendered mesh and collision packet")
	check_compact_brick_survey()
	var sealed:RefCounted=core.capture_edit_field(bounds,state.revision,build_epoch)
	var lane:RefCounted=sealed.capture_contact_core(bounds,state.revision,build_epoch)
	var neighbor:RefCounted=sealed.capture_contact_core(Rect2i(1008,992,16,16),state.revision,build_epoch)
	var roots:=PackedVector3Array()
	for i in 512:
		roots.append(point+Vector3((i%13)*.17-1.0,((i/13)%8)*.19-.6,(i%19)*.23-1.8))
	var support:=Codec.command(40,[state.revision,roots.size()])
	support.append_array(roots.to_byte_array())
	var retained_support:PackedByteArray=core.execute(support)
	var reference_density:=Codec.command(31,[state.revision,roots.size()])
	reference_density.append_array(roots.to_byte_array())
	check(Codec.reply_ok(retained_support) and retained_support==sealed.execute(support) and retained_support.slice(20,20+4*roots.size())==core.execute(reference_density).slice(20),"Sealed root queries preserve the uncached density interpolation order and authoritative paving")
	var remote:=Codec.command(40,[state.revision,1])
	remote.append_array(PackedVector3Array([Vector3(800,40,800)]).to_byte_array())
	check(not Codec.reply_ok(lane.execute(remote)),"A sealed support reader rejects probes outside its captured pages")
	check(lane!=null and neighbor!=null and sealed.capture_contact_core(Rect2i(864,864,32,32),state.revision,build_epoch)==null,"worker views share only the captured extent")
	check(not Codec.reply_ok(sealed.execute(Codec.brush(point,point,4,0,false,0))) and not Codec.reply_ok(lane.execute(Codec.command(12))) and not lane.has_method("restore_field_patch"),"readers reject writes, reset and cancellation of another reader")
	sealed=null
	var contact_packet:=Codec.command(43,[state.revision,build_epoch,1008,40,1008])
	var pinned_boundary:PackedByteArray=core.execute(contact_packet)
	check(lane.execute(owner)==shared_mesh and neighbor.execute(contact_packet)==pinned_boundary,"borrowed pages retain exact terrain, physics and water across release of the parent view")
	var counters:Dictionary=neighbor.surface_column_stats()
	check(counters.columns>0 and counters.meshes==1 and counters.contacts==1 and counters.bytes<=4*1024*1024 and lane.surface_column_stats()==counters,"renderer, collider and adjacent water share one bounded set of extracted surface columns")
	check(not Codec.reply_ok(neighbor.execute(Codec.command(43,[state.revision,build_epoch,872,40,872]))),"an out-of-bounds water contact cannot synthesize missing terrain")
	for coord in [Vector3i(1008,40,1008),Vector3i(1004,36,1004),Vector3i(992,40,992)]:
		var contact:=Codec.command(43,[state.revision,build_epoch,coord.x,coord.y,coord.z])
		var actual:PackedByteArray=frozen.execute(contact)
		check(Codec.reply_ok(actual) and actual==core.execute(contact),"shared reconstruction reproduces water triangles, samples and solids at "+str(coord))
	# Seed a four-owner rim at a regional shoreline. Two outstanding edits
	# invalidate overlapping prisms on either side of the cell-owner seam.
	check(Codec.reply_ok(core.execute(Codec.brush(point,point,9,0,true,2))),"author both sides of the resident seam before the local cuts")
	check(neighbor.execute(contact_packet)==pinned_boundary and lane.execute(owner)==shared_mesh,"advancing the live density revision leaves both sealed workers on their original geometry")
	check(lane.execute(support)==retained_support and not Codec.reply_ok(core.execute(support)),"Support retains the pre-edit field while the authority applies the next revision")
	for x in [976,992,1008]:
		for z in [976,992,1008]:
			check(Codec.reply_ok(core.execute(Codec.command(44,[x,z,16,1,build_epoch]))),"resident triangle baseline populates")
	for brush_center in [Vector3(1007,40,1008),Vector3(1009,41,1007)]:
		var candidates:Dictionary={}
		for x in [960,976,992,1008,1024]:
			for z in [976,992,1008,1024]:
				var key:=Vector3i(x,z,16)
				candidates[key]=core.execute(Codec.command(1,[x,z,16,1,build_epoch]))
		var before:Dictionary=core.field_patch_state()
		var receipt:Dictionary=core.execute_edit_with_writes(Codec.brush(brush_center,brush_center,3,0,false,0),true)
		check(Codec.reply_ok(receipt.reply),"seam excavation accepted")
		var writes:PackedByteArray=receipt.get("writes",PackedByteArray())
		check(writes.size()>12 and writes.decode_u32(0)==1 and writes.decode_u32(4)==before.revision and writes.decode_u32(8)==receipt.reply.decode_u32(12),"seam repair receives actual writes for the committed revision")
		var retained:=0
		var rebuilt:=0
		for key:Vector3i in candidates:
			var item:={"key":key,"retain_if_untouched":true}
			if preload("res://addons/volumetric_terrain/terrain_backend.gd")._surface_unchanged(item,[receipt.surface_owners]):
				var after:PackedByteArray=core.execute(Codec.command(1,[key.x,key.y,key.z,1,build_epoch]))
				var prior:PackedByteArray=candidates[key]
				check(Codec.reply_ok(after) and Codec.reply_ok(prior) and after.slice(16)==prior.slice(16),"retained owner matches a fresh render and collision packet "+str(key))
				retained+=1
			else:rebuilt+=1
		check(retained>0 and rebuilt>0,"seam edit retains neighbours and rebuilds touched owners")
	state=core.field_patch_state()
	var updated:RefCounted=core.capture_contact_core(bounds,state.revision,build_epoch)
	for width:int in [16,32]:
		var key:=Vector3i(992,992,width)
		var full:PackedByteArray=core.execute(Codec.command(1,[key.x,key.y,width,1,build_epoch]))
		var reference_pages:Array=ClassDB.class_call_static("NativeTerrainCollision","triangle_pages",key,Codec.decode_mesh(full.slice(16)).arrays)
		var page_arrays:Array=[]
		for page:Dictionary in reference_pages:page_arrays.append(page.arrays)
		var rim:Array=ClassDB.class_call_static("NativeTerrainCollision","triangle_page_rim",key,page_arrays)
		var full_arrays:Array=Codec.decode_mesh(full.slice(16)).arrays
		if DisplayServer.get_name()!="headless":check_render_upload(full_arrays)
		check(rim.size()==2 and ClassDB.class_call_static("NativeTerrainCollision","matching_cut_boundary",key,15,rim[0],rim[1],full_arrays[Mesh.ARRAY_VERTEX],full_arrays[Mesh.ARRAY_INDEX]),"partial publication preserves the full contact perimeter")
		var count:=(width/8)*(width/8)
		check(not Codec.reply_ok(core.execute(Codec.command(47,[key.x,key.y,width,1,state.revision+1,build_epoch]))),"a superseded triangle page read cannot publish")
		check(not Codec.reply_ok(core.execute(Codec.command(47,[key.x,key.y,width,1<<count,state.revision,build_epoch]))),"out of bounds triangle page request rejects")
		for mask:int in [1,(1<<(count-1)),(1<<count)-1]:
			var payload:PackedByteArray=core.execute(Codec.command(47,[key.x,key.y,width,mask,state.revision,build_epoch]))
			var pages:=Codec.decode_triangle_pages(payload,key,mask,state.revision)
			check(not pages.is_empty(),"direct triangle page request succeeds")
			for page:Dictionary in pages:
				var canonical_page:Dictionary=reference_pages[page.brick_bottom]
				check(page.arrays==canonical_page.arrays and page.faces==canonical_page.faces,"direct page %d of %d matches all canonical render channels and collision faces"%[page.brick_bottom,width])
	check(updated!=null,"changed triangle reader captures resident geometry")
	if updated!=null:
		for x in [992,1008]:
			for z in [992,1008]:
				var reference:PackedByteArray=core.execute(Codec.command(1,[x,z,16,1,build_epoch]))
				var repaired:PackedByteArray=updated.execute(Codec.command(20,[x,z,16,1,build_epoch]))
				check(Codec.reply_ok(repaired) and repaired.slice(12)==reference.slice(12),"replayed and reconstructed triangles match fresh render and collision")
		check(updated.execute(Codec.command(45)).decode_u64(12)>0,"unchanged terrain triangles reused after overlapping edits")
	frozen=core.capture_contact_core(bounds,state.revision,build_epoch)
	var packet:=Codec.command(42,[992,992,32])
	packet.append_array(PackedFloat32Array([point.x,point.y,point.z,32.0]).to_byte_array())
	packet.append_array(PackedInt32Array([1,992,992,1024,1024,state.revision,build_epoch]).to_byte_array())
	var prior:PackedByteArray=core.execute(packet)
	check(Codec.reply_ok(prior),"reference contact includes regional generator and authored samples")
	# Seed the outer rim before first authoring the pages intersected by the
	# large excavation. Page admission exposes the basal band outside the brush.
	for x in [944,960,976]:
		for z in [960,976,992]:
			check(Codec.reply_ok(core.execute(Codec.command(44,[x,z,16,1,build_epoch]))),"pre-edit rim is resident")
	check(Codec.reply_ok(core.execute(Codec.brush(point,point,32,1,false,0))),"authority advances independently")
	state=core.field_patch_state()
	var rim:RefCounted=core.capture_contact_core(Rect2i(944,960,48,48),state.revision,build_epoch)
	check(rim!=null,"newly authored page rim fits the edit snapshot")
	if rim!=null:
		for z in [976,992]:
			var expected:PackedByteArray=core.execute(Codec.command(1,[960,z,16,1,build_epoch]))
			var actual:PackedByteArray=rim.execute(Codec.command(20,[960,z,16,1,build_epoch]))
			check(Codec.reply_ok(actual) and actual.slice(12)==expected.slice(12),"page admission preserves every sealed-floor triangle")
		check(rim.execute(Codec.command(45)).decode_u64(12)>0,"page admission replays unchanged faces while adding the sealed floor")
	var cut_reader:RefCounted=core.capture_contact_core(Rect2i(976,976,64,64),state.revision,build_epoch)
	check(cut_reader!=null,"full excavation fits a bounded edit reader")
	if cut_reader!=null:
		for x in [976,1008,1036]:
			for z in [976,1008,1036]:
				for y in [4,8,36,40]:
					var contact:=Codec.command(43,[state.revision,build_epoch,x,y,z])
					var local:PackedByteArray=cut_reader.execute(contact)
					check(Codec.reply_ok(local) and local==core.execute(contact),"full excavation cell index agrees with ordinary water contact at "+str(Vector3i(x,y,z)))
	check(not Codec.reply_ok(core.execute(packet)),"stale contact packet rejected on live authority")
	check(frozen!=null and frozen.execute(packet)==prior,"isolated contact produces byte-identical geometry after live edit")
	store.close()
	print("TERRAIN_FIELD_PATCH checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

func check_compact_brick_survey()->void:
	var authority:RefCounted=ClassDB.instantiate("TerrainCore")
	var p:=Vector3(112,200,112)
	authority.execute(Codec.command(6,[1703,3]))
	authority.execute(Codec.brush(p,p,32,1,true,2))
	authority.execute(Codec.brush(p,p,16,1,false,0))
	var revision:int=authority.field_patch_state().revision
	var epoch:int=authority.execute(Codec.command(13)).decode_u32(12)
	var reader:RefCounted=authority.capture_edit_field(Rect2i(96,96,32,32),revision,epoch)
	var origins:=PackedInt32Array([112,200,112,88,200,112,96,200,112,12,200,12])
	var classes:PackedByteArray=reader.classify_water_bricks(origins,revision,epoch)
	check(classes==PackedByteArray([1,2,0,0]) and reader.classify_water_bricks(origins,revision+1,epoch).is_empty(),"a sealed field distinguishes air, solid, crossing and unsurveyed water receivers on its exact revision")
	for i in 3:
		var command:=Codec.command(43,[revision,epoch,origins[3*i],200,112])
		var raw:PackedByteArray=authority.execute(command)
		var exact:PackedByteArray=reader.execute(command)
		check(exact==raw and Codec.reply_ok(exact) and ((exact.decode_u32(24)>0)==(i==2)),"receiver classification agrees with the authoritative clipped triangle packet")
	var planes:=PackedInt32Array([108,184,108,112,184,112])
	var survey:PackedByteArray=reader.classify_water_bricks(planes,revision,epoch,true)
	var reference:=PackedByteArray()
	var identical:=survey.size()==34 and survey[0]==3 and survey.slice(0,17)==survey.slice(17,34)
	for i in 2:
		var x:=planes[3*i]
		var z:=planes[3*i+2]
		var packet:PackedByteArray=authority.execute(Codec.command(43,[revision,epoch,x,184,z]))
		identical=identical and Codec.reply_ok(packet) and packet.decode_u32(24)>0
		for v in packet.decode_u32(20):
			var offset:=28+12*v
			packet.encode_float(offset,packet.decode_float(offset)-x)
			packet.encode_float(offset+8,packet.decode_float(offset+8)-z)
		if i==0:reference=packet
		else:identical=identical and reference==packet
	check(identical,"horizontal receiver strata reproduce every extracted triangle, interpolated density and solid mask under translation")
