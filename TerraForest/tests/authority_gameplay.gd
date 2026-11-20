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
		print("GAME_AUTHORITY ",JSON.stringify({"revision":game.terrain.published_revision,"density":Array(received[0].values),"depth":depths,"water_ml":game.lakes.water.statistics().water_ml}))
