# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var checks:=0
var failures:=0
var folder:="res://reports/gathering_lifecycle"
var drive_host:=false
func _initialize()->void:
	physics_frame.connect(drive_zombies);run.call_deferred()
func drive_zombies()->void:
	# Freeze only the fixture player/camera. Keep the actual zombie host's
	# normal residency/menu/readiness lifecycle running on physics ticks.
	if not drive_host or not is_instance_valid(game) or game.shutdown_requested:return
	game.zombies.update(1.0/Engine.physics_ticks_per_second,game.player.global_position,game.corpse_loot.ui.allowed() and not game.session_menu.visible_ui() and not game.player_hud.inventory_open,not game.fly)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func picture(name:String)->void:
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func aim(point:Vector3,offset:Vector3)->void:
	game.camera.global_position=point+offset;game.camera.look_at(point)
	game.app_focused=true;game.fly=false;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func run()->void:
	var slot:="";var reopening:=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
		if arg=="--reopen-loop":reopening=true
		if arg.begins_with("--gather-evidence="):folder=arg.trim_prefix("--gather-evidence=")
	if not slot.begins_with("gather_lifecycle_") or not slot.is_valid_identifier():quit(2);return
	DirAccess.make_dir_recursive_absolute(folder)
	var expected_path:=OS.get_user_data_dir().path_join("gathering_lifecycle_"+slot+".bin")
	if not reopening and (FileAccess.file_exists("user://worlds/"+slot+".trw") or FileAccess.file_exists(expected_path)):quit(2);return
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=false;game.max_fps=60;game.background_fps=60;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active and game.terrain.world_ready,"actual playable world and corpse save component initialize")
	if game.loading_active:quit(1);return
	game.set_physics_process(false);game._clear_motion();game.zombies.population_enabled=false;game.zombies.clear();game.zombies.enabled=true;game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED;drive_host=true
	var inv:RefCounted=game.player_hud.inventory
	var expected:Dictionary={}
	if reopening:
		expected=FileAccess.open(expected_path,FileAccess.READ).get_var()
		if game.corpse_loot.store.capture_corpse_snapshot()!=expected.corpses:
			var actual:PackedByteArray=game.corpse_loot.store.capture_corpse_snapshot();var first:=0
			while first<mini(actual.size(),expected.corpses.size()) and actual[first]==expected.corpses[first]:first+=1
			print("CORPSE_PACKET_DIFFERENCE byte=",first," expected_size=",expected.corpses.size()," actual_size=",actual.size())
			var file:=FileAccess.open(folder.path_join("expected.bin"),FileAccess.WRITE);file.store_buffer(expected.corpses);file.close()
			file=FileAccess.open(folder.path_join("actual.bin"),FileAccess.WRITE);file.store_buffer(actual);file.close()
		check(game.corpse_loot.store.capture_corpse_snapshot()==expected.corpses,"fresh process restores exact corpse records, poses and inventories")
		check(inv.capture_storage_snapshot()==expected.inventory,"fresh process restores matching player inventory")
		check(game.ecosystem.harvest_state.contains(expected.tree) and game.ground_cover.removed.mask(PackedInt64Array([expected.rock]))[0]!=0,"felled tree and mined boulder stay harvested after reopening")
		deadline=Time.get_ticks_msec()+8000
		while game.corpse_loot.active.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		if game.corpse_loot.active.is_empty():
			print("CORPSE_RESIDENCY ",JSON.stringify({"focused":game.app_focused,"player":str(game.player.global_position),"camera":str(game.camera.global_position),"loading":game.loading_active,"pending":game.terrain.pending_edit,"menu":game.session_menu.visible_ui(),"inventory":game.player_hud.inventory_open,"query":str(game.corpse_loot.store.nearby_corpses(game.player.global_position,80.0,PackedInt64Array()))}))
			for id:int in game.corpse_loot.store.corpse_ids():
				var record:Dictionary=game.corpse_loot.store.corpse(id);var point:Vector3=record.position
				if record.pose.size()==180:point=Vector3(record.pose[3],record.pose[7],record.pose[11])
				var bounds:=AABB(point-Vector3(2,1,2),Vector3(4,3,4))
				print("CORPSE_GATE ",JSON.stringify({"point":str(point),"distance":point.distance_to(game.player.global_position),"terrain":game.terrain.is_collision_region_ready(bounds),"structures":game.structures.is_collision_region_ready(bounds),"trees":game.vegetation.is_collision_region_ready(bounds),"rocks":game.ground_cover.rock_collision.is_collision_region_ready(bounds)}))
		check(not game.corpse_loot.active.is_empty(),"saved corpse rematerializes near the player")
		if not game.corpse_loot.active.is_empty():
			var zombie:Node3D=game.corpse_loot.active.values()[0]
			for i in 60:await physics_frame
			var torso:Vector3=zombie.physical_bones[zombie.PARTS.torso.bone].global_position
			aim(torso,Vector3(0,1.5,2.2));await picture("corpse_restored")
			print("CORPSE_RESTORED ",JSON.stringify({"visible":zombie.is_visible_in_tree(),"mode":zombie.process_mode,"torso":str(torso),"camera":str(game.camera.global_position),"target":game.corpse_loot.aimed_id(),"stats":zombie.anatomy.ragdoll_stats()}))
			var floor_query:=PhysicsRayQueryParameters3D.create(torso+Vector3.UP*3,torso-Vector3.UP*3,1)
			var floor_hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(floor_query)
			print("CORPSE_RESTORED_GEOMETRY ",JSON.stringify({"mesh_center":str(zombie._bake_cpu(zombie.part_meshes.torso,Transform3D.IDENTITY).get_aabb().get_center()),"ground":str(floor_hit.get("position",Vector3.ZERO)),"root":str(zombie.global_position),"saved":str(game.corpse_loot.store.corpse(int(zombie.get_meta("corpse_identity",0))).pose.slice(0,12))}))
			check(zombie.is_visible_in_tree() and game.corpse_loot.aimed_id()==int(zombie.get_meta("corpse_identity",0)),"restored corpse is visible and targetable through its real skinned body")
			for frame in 300:await physics_frame
			check(zombie.anatomy.ragdoll_stats().sleeping==15,"restored intact corpse settles with all physical limbs present")
			var initial:Vector3=zombie.physical_bones.Spine2.global_position
			zombie.physical_bones.Spine2.apply_central_impulse(Vector3(6,1,0))
			var displacement:=0.0;var bounded:=true
			for frame in 360:
				await physics_frame
				displacement=maxf(displacement,zombie.physical_bones.Spine2.global_position.distance_to(initial))
				for body:PhysicalBone3D in zombie.physical_bones.values():bounded=bounded and body.global_transform.is_finite() and body.global_position.distance_to(zombie.physical_bones.Hips.global_position)<2.5
			check(bounded and displacement>.001 and displacement<2.5 and zombie.anatomy.ragdoll_stats().sleeping==15,"restored corpse responds to a physical push without exploding and settles again")
	else:
		var native:RefCounted=ClassDB.instantiate("NativeGroundCover")
		var rock:Dictionary={};var rock_cell:=Vector2i.ZERO
		for index in 80:
			var cell:=Vector2i(25+index%8,25+index/8)
			var candidates:Dictionary=native.candidates(cell,1703)
			var points:PackedVector3Array=candidates.points;var normals:=PackedVector3Array()
			for j in points.size():points[j].y=50;normals.append(Vector3.UP)
			var placed:Dictionary=native.place(candidates.ids,points,normals)
			var excluded:=PackedByteArray();excluded.resize(placed.ids.size())
			var rows:Array=native.pack(placed.ids,placed.transforms,excluded)
			var large:Dictionary=native.boulder_rows(rows[0])
			if not large.ids.is_empty():rock={"id":large.ids[0],"values":large.transforms.slice(0,12)};rock_cell=cell;break
		check(not rock.is_empty(),"native scatter deterministically supplies very large gathering stones")
		if rock.is_empty():game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();quit(1);return
		var values:PackedFloat32Array=rock.values
		var pose:=Transform3D(Basis(Vector3(values[0],values[4],values[8]),Vector3(values[1],values[5],values[9]),Vector3(values[2],values[6],values[10])),Vector3(values[3],values[7],values[11]))
		var rows:Array=[]
		for s in 9:rows.append({"ids":PackedInt64Array(),"transforms":PackedFloat32Array()})
		rows[0]={"ids":PackedInt64Array([rock.id]),"transforms":values}
		var authored:Array[Transform3D]=[]
		game.ground_cover._publish(rock_cell,rows,authored,PackedByteArray())
		game.ground_cover._dirty.erase(rock_cell);game.ground_cover._pending.erase(rock_cell)
		var start:Vector3=pose*Vector3(0,.05,.44);var end:Vector3=pose*Vector3(0,.05,.26)
		var probe:Dictionary=game.ground_cover.picker.pick(start,end)
		check(probe.hit and probe.large and probe.id==rock.id,"native target proxy identifies the large stone")
		var before:Dictionary=inv.snapshot()
		var denied:Dictionary=game.ground_interaction.collect(start,end,inv,true,{})
		check(not denied.ok,"ordinary pickup cannot bypass boulder mining")
		var mined:Dictionary=game.ground_interaction.collect(start,end,inv,true,{},rock.id)
		check(mined.ok and inv.can_afford(PackedInt64Array([201,24]),inv.snapshot().revision).ok,"mined boulder grants 24 stone and removes its saved identity")
		check(not game.ground_interaction.collect(start,end,inv,true,{},rock.id).ok,"mined boulder cannot grant stone twice")
		expected.rock=rock.id
		for key:Vector2i in game.ground_cover.resident:
			if key==rock_cell:continue
			var natural:Dictionary=native.boulder_rows(game.ground_cover.resident[key][0])
			if natural.ids.is_empty():continue
			var data:PackedFloat32Array=natural.transforms
			aim(Vector3(data[3],data[7],data[11]),Vector3(10,5,12))
			for i in 15:await process_frame
			await picture("boulder_world");break
		var tree_id:=0
		deadline=Time.get_ticks_msec()+10000
		while tree_id==0 and Time.get_ticks_msec()<deadline:
			for id:int in game.vegetation.renderer.roots:
				if id<=36864:tree_id=id;break
			if tree_id==0:await process_frame
		check(tree_id>0,"natural tree is resident for actual harvest")
		if tree_id>0:
			var tree_pose:Transform3D=game.vegetation.renderer.roots[tree_id].t
			var chopped:Dictionary=game.ecosystem.harvest_root(tree_id,inv,Vector3.RIGHT)
			check(chopped.ok and game.vegetation.falling_trees.count()==1 and not game.vegetation.renderer.roots.has(tree_id),"successful harvest transfers the tree into native toppling presentation")
			game.vegetation.renderer.hide()
			game.tool_view.hide()
			aim(tree_pose.origin+Vector3(5,5,0),Vector3(15,7,22))
			for i in 42:await process_frame
			await picture("tree_falling")
			for i in 100:await process_frame
			await picture("tree_fallen")
			game.vegetation.renderer.show();game.tool_view.show()
			expected.tree=tree_id
		var zombie:Node3D=null
		for offset:Vector3 in [Vector3(3,0,0),Vector3(-3,0,0),Vector3(0,0,3),Vector3(0,0,-3)]:
			zombie=game.zombies.spawn_at(game.player.global_position+offset)
			if zombie!=null:break
		check(zombie!=null,"real encounter zombie spawns on supported terrain")
		if zombie!=null:
			zombie.receive_hit("torso",1000,zombie.global_position+Vector3.UP,Vector3.ZERO)
			var id:int=zombie.get_meta("corpse_identity",0)
			check(not zombie.alive and id>0 and game.corpse_loot.store.has_contents(id),"death creates a stable native loot inventory exactly once")
			for i in 150:await physics_frame
			var point:Vector3=zombie.physical_bones[zombie.PARTS.torso.bone].global_position
			aim(point,Vector3(0,1.3,1.4));await process_frame
			check(game.corpse_loot.aimed_id()==id,"actual skinned corpse targeting finds its storage")
			check(preload("res://demo/world_interaction.gd").new().interact(game) and game.corpse_loot.ui.opened,"normal E interaction opens corpse inventory")
			if game.corpse_loot.ui.opened:
				await picture("corpse_inventory")
				var paused_pose:Transform3D=zombie.physical_bones["Spine2"].global_transform
				for i in 20:await physics_frame
				check(zombie.physical_bones["Spine2"].global_position.distance_to(paused_pose.origin)<.001,"opening loot freezes the corpse while gameplay is paused")
				game.corpse_loot.ui.storage_list.select(0);game.corpse_loot.ui.quantity.get_line_edit().text="1"
				check(game.corpse_loot.ui.move_selected(false),"normal native storage transfer takes corpse loot")
				game.corpse_loot.ui.close()
			game.corpse_loot.retain(zombie)
			var packet:PackedByteArray=game.corpse_loot.capture()
			check(not game.corpse_loot.store.restore_corpse_snapshot(packet.slice(0,packet.size()-1)) and game.corpse_loot.store.capture_corpse_snapshot()==packet,"truncated corpse packet is rejected without mutation")
			expected.corpses=packet;expected.inventory=inv.capture_storage_snapshot()
		var found_natural:=false
		deadline=Time.get_ticks_msec()+10000
		while not found_natural and Time.get_ticks_msec()<deadline:
			for key:Vector2i in game.ground_cover.resident:
				if key==rock_cell:continue
				var natural:Dictionary=native.boulder_rows(game.ground_cover.resident[key][0])
				if natural.ids.is_empty():continue
				var data:PackedFloat32Array=natural.transforms
				aim(Vector3(data[3],data[7],data[11]),Vector3(10,5,12));game.tool_view.hide()
				for i in 15:await process_frame
				await picture("boulder_world");game.tool_view.show();found_natural=true;break
			if not found_natural:await process_frame
		check(found_natural,"normal ground-cover streaming publishes a naturally supported boulder")
		var saved:Array=[];game.terrain.save_completed.connect(func(ok:bool):saved.append(ok))
		game.terrain.changed_since_save=true;game.terrain.save_world();deadline=Time.get_ticks_msec()+20000
		while saved.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
		check(not saved.is_empty() and saved[0],"normal compound save publishes corpse loot and player inventory together")
		expected.corpses=game.corpse_loot.store.capture_corpse_snapshot()
	game.shutdown_requested=true
	check(await game.terrain.shutdown_after_edits(),"normal world shutdown drains")
	if not reopening and failures==0:
		expected.corpses=game.corpse_loot.store.capture_corpse_snapshot()
		var file:=FileAccess.open(expected_path,FileAccess.WRITE);file.store_var(expected);file.close()
	game.free();await process_frame;await process_frame
	print("GATHERING_LIFECYCLE checks=",checks," failures=",failures," reopen=",reopening);quit(1 if failures else 0)
