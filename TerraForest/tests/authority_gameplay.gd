# SPDX-License-Identifier: 0BSD
extends "water_player_world.gd"
const POINTS:=[Vector3(239,31,224),Vector3(241,31,224),Vector3(256,32,224)]
func run()->void:
	var slot_name:="AuthorityCheck"
	var path:="user://worlds/"+slot_name+".trw"
	if not FileAccess.file_exists(path):quit(2);return
	var original:=FileAccess.get_sha256(path)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(PackedStringArray(["--world-slot="+slot_name,"--snapshot-readonly","--temporary","--no-derived-cache"]),true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	check(await ready("authority_spawn"),"Cold world opens in gameplay")
	if failures==0:
		game.teleport(Vector3(240,40,224))
		check(await ready("authority_shore"),"Lake is resident")
	if "--bucket-checkpoint" in OS.get_cmdline_user_args():
		if failures==0:await save_bucket_checkpoint(path)
		check(FileAccess.get_sha256(path)==original,"Bucket checkpoint preserves the gameplay input")
		game.terrain.shutdown();game.free()
		await process_frame
		quit(failures);return
	if failures==0:
		check(game.terrain.sculpt_sphere(Vector3(240,31,224),3,false,1),"Gameplay admits cross-boundary excavation")
		check(await ready("authority_edit"),"Gameplay finishes water publication")
	if failures==0:await sample_commit()
	if failures==0:
		check(game.terrain.sculpt_sphere(Vector3(240,31,224),2,true,2),"Gameplay deposits material into the wet cross-boundary cut")
		check(await ready("authority_deposit"),"Gameplay finishes water displacement")
	if failures==0:await sample_commit()
	check(FileAccess.get_sha256(path)==original,"Input archive unchanged")
	game.terrain.shutdown();game.free()
	await process_frame
	quit(failures)

func save_bucket_checkpoint(input_path:String)->void:
	var inventory:RefCounted=game.player_hud.inventory
	var state:Dictionary=inventory.snapshot()
	var slot:int=state.slots.find_custom(func(row:Dictionary)->bool:return row.item==401)
	if slot<0:check(false,"Gameplay starter bucket is present");return
	var before:int=game.lakes.water.total_water_ml()
	var transfer:Dictionary=game.lakes.bucket(Vector3(256.25,38,224.25),Vector3(256.25,33,224.25),false,inventory,slot,state.revision)
	check(transfer.ok and before-game.lakes.water.total_water_ml()==1000000,"Gameplay transfers one cubic metre into the saved bucket")
	if not transfer.ok:return
	var archive:RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var output:=ProjectSettings.globalize_path("user://authority/BucketCheck.trw")
	if FileAccess.file_exists(output) or not archive.acquire(output):check(false,"Disposable bucket checkpoint is available");return
	var original:Dictionary=archive.decode(FileAccess.get_file_as_bytes(input_path))
	var catalog:PackedByteArray=game.lakes.water.snapshot_catalog(original.sections.volumetric_water)
	original.sections.volumetric_water=game.lakes.water.capture_streaming_snapshot(catalog)
	original.sections.player_loadout=game.player_hud.capture_snapshot()
	var limit:=0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--checkpoint-limit="):limit=int(arg.trim_prefix("--checkpoint-limit="))
	var checkpoint:PackedByteArray=archive.encode(original.sections)
	check(not checkpoint.is_empty() and checkpoint.size()<=limit and archive.publish(output,checkpoint)==OK,"Publish matching gameplay inventory and water within the capture reservation")
	archive.release()
	var hud=game.player_hud
	if game.session_menu.developer:game.session_menu.toggle_developer()
	hud.set_open(true)
	var destination:=31
	hud.drop_stack("player",destination,hud.drag_data("player",slot))
	var moved_slots:Array=inventory.snapshot().slots
	check(moved_slots[destination].water_ml==1000000,"Inventory drag carries the full bucket to the backpack")
	hud.drop_stack("player",slot,hud.drag_data("player",destination))
	hud.set_open(false)
	var filled_quantity:int=game.lakes.water.total_water_ml()
	if not await ready("gameplay_scoop"):check(false,"Gameplay publishes the scooped surface");return
	var pour:Dictionary=game.lakes.bucket(Vector3(256.25,38,224.25),Vector3(256.25,33,224.25),true,inventory,slot,inventory.snapshot().revision)
	if not pour.ok or not await ready("gameplay_pour"):check(false,"Gameplay publishes the poured surface");return
	var after:Dictionary=game.lakes.water.raycast_surface(Vector3(256.25,38,224.25),Vector3(256.25,33,224.25))
	check(after.hit and game.lakes.water.total_water_ml()==before and inventory.snapshot().slots==state.slots,"Gameplay pour restores quantity and slot contents")
	if after.hit:print("GAME_BUCKET ",JSON.stringify({"slot":slot,"water_ml":filled_quantity,"poured_y":after.point.y,"poured_cell":[after.cell.x,after.cell.y,after.cell.z],"move_destination":destination,"moved_slots":moved_slots}))

func sample_commit()->void:
	var token:int=preload("res://addons/volumetric_terrain/surface_tokens.gd").allocate()
	var received:Array=[]
	var callback:=func(reply:Dictionary):
		if reply.token==token:received.append(reply)
	game.terrain.density_batch_ready.connect(callback)
	var requested:=false
	var deadline:=Time.get_ticks_msec()+10000
	while received.is_empty() and Time.get_ticks_msec()<deadline:
		if not requested:requested=game.terrain.request_interpolated_density_batch(PackedVector3Array(POINTS),token)
		await process_frame
	game.terrain.density_batch_ready.disconnect(callback)
	check(not received.is_empty() and received[0].status=="ok","Committed terrain can be sampled")
	if failures==0:
		var depths:Array=[]
		for point in POINTS:depths.append(game.lakes.depth_at(point))
		var target:Dictionary=game.lakes.water.raycast_surface(Vector3(256.25,38,224.25),Vector3(256.25,33,224.25))
		check(target.hit,"A bucket ray intersects the resident lake surface")
		if not target.hit:return
		var normal:Vector3=target.normal
		print("GAME_AUTHORITY ",JSON.stringify({"revision":game.terrain.published_revision,"density":Array(received[0].values),"depth":depths,"water_ml":game.lakes.water.statistics().water_ml,"surface_y":target.point.y,"surface_cell":[target.cell.x,target.cell.y,target.cell.z],"surface_normal":[normal.x,normal.y,normal.z],"inventory":game.player_hud.inventory.snapshot().slots}))
