# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Reference=preload("res://addons/structures/foundation_check.gd")
var checks:=0
var failures:=0
class Backend extends RefCounted:
	var native:RefCounted
class Field extends Node:
	var backend:=Backend.new()
	var world_ready:=true
	var pending_edit:=false
	var stopping:=false
	var diagnostics_pause_streaming:=true
	var epoch:=1
	var density_revision:=0
	var validator:RefCounted
	func request_density_scan(points:PackedVector3Array,token:int,depth:int,interpolated:bool)->bool:
		var values:=PackedFloat32Array()
		for offset in range(0,points.size(),512):
			var part:=points.slice(offset,offset+512)
			var query:=Codec.command(30 if depth else 31 if interpolated else 29,[density_revision,part.size(),depth] if depth else [density_revision,part.size()])
			query.append_array(part.to_byte_array())
			var reply:PackedByteArray=backend.native.execute(query)
			if not Codec.reply_ok(reply):return false
			values.append_array(reply.slice(20).to_float32_array())
		validator.call_deferred("receive",{"token":token,"status":"ok","epoch":epoch,"revision":density_revision,"values":values})
		return true
class Doors extends RefCounted:
	var collection:Node3D
class Game extends Node:
	var terrain:Field
	var structures:Node3D
	var doors:=Doors.new()
	var shutdown_requested:=false
	var editor_calls:=0
	func _accept_composed_prefab(_value:Dictionary)->void:editor_calls+=1
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func game_for(height:float=47.75)->Game:
	var game:=Game.new();root.add_child(game)
	game.terrain=Field.new();game.add_child(game.terrain)
	game.terrain.backend.native=ClassDB.instantiate("TerrainCore")
	game.terrain.backend.native.execute(Codec.command(6,[1703,2]))
	game.terrain.backend.native.execute(Codec.graded_bed(Vector3(480,height,500),Vector3(540,height,500),12,8,12,1))
	game.terrain.density_revision=game.terrain.backend.native.execute(Codec.command(0)).decode_u32(12)
	game.structures=preload("res://addons/structures/structures_world.gd").new();game.add_child(game.structures)
	assert(game.structures.prepare())
	var mesh:=BoxMesh.new();mesh.size=Vector3(.2,.4,.2)
	game.doors.collection=game.structures.register_model("architecture/wooden_door/v1",mesh)
	assert(game.doors.collection!=null)
	return game
func asset_for()->Resource:
	var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
	assert(asset.configure(PackedInt32Array([0,0,0,1])))
	asset.set_meta("site_surface_offset",1);asset.set_meta("site_sample_band",1)
	assert(asset.configure_attachment_envelope(AABB(Vector3.ZERO,Vector3(1,2,1))))
	assert(asset.configure_model_attachments([{"model":"architecture/wooden_door/v1","transform":Transform3D(Basis(),Vector3(.5,1.5,.5))}]))
	return asset
func lots_for(asset:Resource)->Array:
	var lots:Array=[]
	for i in 12:lots.append({"asset":asset,"origin":Vector3i(490+i*4,47,500),"rotation":i%4,"label":"Shared template "+str(i)})
	return lots
func finish(job:RefCounted)->Dictionary:
	var deadline:=Time.get_ticks_msec()+30000
	while not job.advance() and Time.get_ticks_msec()<deadline:await process_frame
	if Time.get_ticks_msec()>=deadline:
		job.cancel()
		while not job.advance():await process_frame
		check(false,"native job completes before test deadline")
	return job.get_result()
func run()->void:
	var source:=asset_for();var lots:=lots_for(source)
	var reference:=game_for();var old_begin:=Time.get_ticks_usec()
	reference.terrain.validator=Reference.new()
	for lot:Dictionary in lots:
		check(reference.terrain.validator.begin(reference.terrain,lot.asset,lot.origin,lot.rotation),"reference contact check starts")
		while reference.terrain.validator.status=="checking":
			reference.terrain.validator.tick(reference.terrain);await process_frame
		check(reference.terrain.validator.status=="supported","reference accepts supported template")
		var publisher:RefCounted=ClassDB.instantiate("NativePrefabPlacement")
		check(publisher.place(reference.structures.blocks,lot.asset,lot.origin,lot.rotation,reference.structures.model_collections(),[]).ok,"reference atomic template publication")
	var reference_us:=Time.get_ticks_usec()-old_begin
	var game:=game_for();var job:RefCounted=ClassDB.instantiate("NativeGenerationBuildings")
	check(job.start(game,lots),"native job accepts repeated immutable templates")
	# Worker owns a private definition; source edits cannot race probe cache writes.
	source.set_meta("site_sample_band",9)
	var outcome:=await finish(job)
	check(outcome.get("ok",false) and outcome.buildings==12 and outcome.definitions==1,"native job reuses one private definition for twelve placements")
	check(game.structures.blocks.capture_snapshot()==reference.structures.blocks.capture_snapshot(),"all block bytes match reference across four rotations")
	check(game.doors.collection.capture_snapshot()==reference.doors.collection.capture_snapshot(),"all ordered model IDs and transforms match reference")
	check(game.editor_calls==0,"generation makes no construction-palette calls")
	check(outcome.checks.size()==12 and outcome.checks.all(func(row:Dictionary):return row.foundation>0 and row.deep_support>0 and row.surfaces==9),"every lot retains foundation, deep support and exposed-surface checks")
	print("GENERATION_BUILDINGS_PROFILE ",JSON.stringify({"reference_us":reference_us,"native":outcome.profile}))
	game.free();reference.free();source=asset_for();lots=lots_for(source)
	for mode:String in ["surface","unsupported","changed","native_changed","epoch","cancelled","not_offline","wide_rotation","wide_band","invalid_contract"]:
		game=game_for(48.0 if mode=="surface" else 47.75)
		var request:Array=lots_for(asset_for())
		if mode=="unsupported":request[0].origin.y=80
		if mode=="not_offline":game.terrain.diagnostics_pause_streaming=false
		if mode=="wide_rotation":request[0].rotation=4294967296
		if mode=="wide_band":
			# Reject wide authoring integers before converting to native int fields.
			request[0].asset.set_meta("site_surface_offset",4294967297)
			request[0].asset.set_meta("site_sample_band",4294967297)
		if mode=="invalid_contract":request[0].asset.set_meta("site_surface_inset",0.5)
		job=ClassDB.instantiate("NativeGenerationBuildings")
		var before:PackedByteArray=game.structures.blocks.capture_snapshot()
		var admitted:bool=job.start(game,request)
		if mode in ["not_offline","wide_rotation","wide_band","invalid_contract"]:check(not admitted,"job rejects invalid admission: "+mode)
		else:
			check(admitted,"rejection fixture starts: "+mode)
			if mode=="changed":game.terrain.density_revision+=1
			if mode=="native_changed":
				# Change the authoritative core without refreshing the scene bridge.
				game.terrain.backend.native.execute(Codec.graded_bed(Vector3(480,48,500),Vector3(540,48,500),12,8,12,1))
			if mode=="epoch":game.terrain.epoch+=1
			if mode=="cancelled":job.cancel()
			var rejected:=await finish(job)
			check(not rejected.get("ok",false),"job rejects "+mode)
		check(game.structures.blocks.capture_snapshot()==before and game.doors.collection.get_ids().is_empty(),"rejected validation publishes no cells or models: "+mode)
		game.free()
	await process_frame
	print("GENERATION_BUILDINGS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
