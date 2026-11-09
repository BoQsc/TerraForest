# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var failures:=0
var folder:=""
var samples:Array=[]
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--destruction-output="):folder=arg.trim_prefix("--destruction-output=")
	run.call_deferred()
func tick()->void:
	game.app_focused=true
	await physics_frame
func run()->void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+90000
	while game.loading_active and Time.get_ticks_msec()<deadline:await tick()
	check(not game.loading_active,"actual world admits destructive workload")
	if game.loading_active:game.free();quit(1);return
	game.player_view.entry.finish();game.session_menu.set_open(false);game._clear_motion()
	game.combat.set_integrity(false);game.combat.set_physics_process(false)
	var base:=Vector3i(game.player.position.floor())+Vector3i(0,4,-6)
	var center:=Vector3(base)+Vector3(2,2,2)
	var word:int=game.structures.blocks.encode_block(1,0,1)
	var records:=PackedInt32Array()
	for y in 4:
		for z in 4:
			for x in 4:records.append_array(PackedInt32Array([base.x+x,base.y+y,base.z+z,word]))
	for cycle in 2:
		for batched in [false,true,true,false]:
			game.combat.effects.clear();await tick()
			game.combat.effects.geometry.clear();game.combat.effects.materials.clear()
			check(game.structures.blocks.set_cells(records),"64-cell structure installs")
			game.structures.blocks.flush_bakes();await tick();await tick()
			var publications:=[0]
			var changed:Callable=func(_bounds:AABB):publications[0]+=1
			game.structures.blocks.cells_changed.connect(changed)
			var started:=Time.get_ticks_usec();var costs:Array=[]
			if batched:game.combat.blast_jobs.assign([{"center":center,"records":records,"offset":0}])
			for at in range(0,records.size(),24*4):
				var began:=Time.get_ticks_usec()
				if batched:game.combat.step_blasts()
				else:
					# Controlled old publication/resource policy; same new removal API,
					# so this deliberately excludes the former undo-allocation cost.
					for i in range(at,mini(at+24*4,records.size()),4):
						game.combat.effects.geometry.clear();game.combat.effects.materials.clear()
						var cell:=Vector3i(records[i],records[i+1],records[i+2])
						# Explicitly retain the former expensive decomposition for
						# the control, even when the normal path uses the binary bake.
						var mesh:Mesh=game.structures.blocks.preview_mesh(1,0)
						game.combat.effects.geometry[Vector2i(1,0)]={"mesh":mesh,"shape":mesh.create_convex_shape(true,true)}
						var distance:float=(Vector3(cell)+Vector3.ONE*.5).distance_to(center)
						game.combat.damage_block(cell,word,maxi(1,roundi(300*(1-distance/5))),center,9*(1-distance/6))
				costs.append(Time.get_ticks_usec()-began);await tick()
			game.structures.blocks.cells_changed.disconnect(changed)
			var removed:=true
			for i in range(0,records.size(),4):removed=removed and game.structures.blocks.get_cell(Vector3i(records[i],records[i+1],records[i+2]))==0
			check(removed and game.combat.effects.fragments.size()==64,"all blocks become physical debris with unchanged damage falloff")
			check(publications[0]==(3 if batched else 64),"transaction publication count matches bounded policy")
			samples.append({"batched":batched,"cycle":cycle,"batch_us":costs,"publications":publications[0],"elapsed_us":Time.get_ticks_usec()-started})
			game.structures.blocks.flush_bakes();await tick();await tick()
	if not folder.is_empty():
		FileAccess.open(folder.path_join("destruction.json"),FileAccess.WRITE).store_string(JSON.stringify(samples))
		if DisplayServer.get_name()!="headless":
			game.camera.look_at(center);await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join("debris.png"))
	print("DESTRUCTION_WORLD_COST ",JSON.stringify(samples))
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"destruction publishes before shutdown")
	game.free();await process_frame;await process_frame
	print("DESTRUCTION_WORLD_COST failures=",failures);quit(1 if failures else 0)
