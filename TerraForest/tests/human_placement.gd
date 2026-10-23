# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func pose(view:Node3D,time:float)->void:
	view.animation_player.play(view.clips.FP_Place_Relaxed,0.0)
	view.animation_player.seek(time,true)
	view.animation_player.pause()
	view.animation_player.advance(0)
func run()->void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"actual temporary world loads")
	if game.loading_active:game.free();quit(1);return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true
	game.session_menu.set_open(false);game.zombies.clear()
	var view:Node3D=game.tool_view.human
	game.tool_view.equip(0);view.set_process(false)
	check(view.clips.size()==72 and view.clips.has("FP_Place_Relaxed"),"original 71 clips and new Blender action coexist")
	var animation:Animation=view.animation_player.get_animation(view.clips.FP_Place_Relaxed)
	check(is_equal_approx(animation.length,.9) and animation.loop_mode==Animation.LOOP_NONE,"placement is a 0.9-second one-shot")
	var bone_only:=true
	for track in animation.get_track_count():
		bone_only=bone_only and animation.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D]
	check(bone_only,"placement contains no gameplay, audio or method tracks")
	check(view.place() and view.placement_active,"empty-hand gesture starts")
	var remaining:float=view.action_remaining
	check(not view.place() and view.action_remaining==remaining,"held placement never resets an unfinished gesture")
	pose(view,.4333333)
	var skeleton:Skeleton3D=view.model.find_child("Skeleton3D",true,false)
	var hand:Vector3=skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin
	var finger:Vector3=skeleton.get_bone_global_pose(skeleton.find_bone("RightHandIndex3")).origin
	var forearm:Vector3=skeleton.get_bone_global_pose(skeleton.find_bone("RightForeArm")).origin
	var palm_axis:Vector3=skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).basis.y.normalized()
	check(palm_axis.dot((hand-forearm).normalized())>.995,"wrist remains straight and aligned with the forearm")
	check(hand.y<1.55,"whole hand is held low")
	var tip:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("RightHandIndex3"))
	var screen:Vector2=game.camera.unproject_position(tip.origin+tip.basis.y*.027)
	check(screen.x>0 and screen.x<root.size.x and screen.y>0 and screen.y<root.size.y*.9,"index fingertip stays inside the first-person frame above the belt")
	var empty_pose:=skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))
	game.tool_view.equip(1);check(not view.placement_active and view.active_clip=="FP_Pickaxe_Idle","equipment switch cancels gesture and restores authored tool idle")
	check(game.tool_view.place(),"placement can temporarily free the equipped hand")
	pose(view,.4333333)
	check(skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).is_equal_approx(empty_pose),"placement pose is independent of the previously equipped tool")
	for mesh in view.meshes:
		if String(mesh.name).to_lower().begins_with("equipment"):check(not mesh.visible,"gesture hides "+String(mesh.name))
	view._process(1.0)
	check(not view.placement_active and view.active_clip=="FP_Pickaxe_Idle","completed gesture restores selected equipment")
	game.tool_view.equip(3);game.tool_view.place();game.tool_view._process(0)
	check(not game.tool_view.tools[3].visible,"legacy construction preview is hidden during the empty-hand action")
	view._process(1.0);game.tool_view._process(0)
	check(game.tool_view.tools[3].visible,"construction preview returns after the action")
	game.tool_view.equip(0)
	# Native authored block targeting exercises the real success/removal path.
	var cell:=Vector3i(game.player.global_position.floor())+Vector3i(0,1,-3)
	game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,1]))
	game.camera.look_at(Vector3(cell)+Vector3.ONE*.5)
	game.structure_prefab_index=-1;game.structure_shape=1;game.structure_material=0
	game.construction_inventory.gameplay=false
	game._edit_structure(false)
	check(view.placement_active,"accepted native block placement plays the gesture")
	game.tool_view.equip(0);game._edit_structure(true)
	check(not view.placement_active,"block removal does not play a placement gesture")
	# A queued terrain addition exercises the shared accepted-edit callback.
	var terrain_cell:=Vector3i(game.player.global_position.floor())+Vector3i(4,3,-4)
	check(game.stroke_buffer.push_cube(terrain_cell,1),"isolated terrain-fill sample is admitted")
	game._consume_stroke()
	check(view.placement_active,"accepted terrain fill plays the gesture")
	game.tool_view.equip(0)
	var output:="res://reports/human_placement"
	DirAccess.make_dir_recursive_absolute(output+"/frames")
	if DisplayServer.get_name()!="headless":
		# Render the actual runtime rig at the normal first-person camera, then
		# retain a deterministic two-cycle sequence for the Blender video encoder.
		game.camera.rotation=Vector3.ZERO
		game.tool_view.place()
		pose(view,.4333333)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/runtime_hud.png")
		for child in game.get_children():
			if child is CanvasLayer:child.hide()
		for frame in 57:
			pose(view,float(frame%29)/30.0)
			await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image()
			image.save_png(output+"/frames/%03d.png"%frame)
			if frame in [5,13,23]:image.save_png(output+"/runtime_%02d.png"%frame)
	var report:={"checks":checks,"failures":failures,"clip_seconds":animation.length,"tracks":animation.get_track_count(),"scope":"Actual host placement feedback, original equipment restoration, animation-only bone tracks, lowered hand with neutral wrist and rendered first-person playback. No collision, navigation or save schema changes."}
	FileAccess.open(output+"/result.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	game.shutdown_requested=true;game.terrain.backend.disable_snapshot_writes();await game.terrain.shutdown_after_edits();game.free()
	print("HUMAN_PLACEMENT checks=",checks," failures=",failures);quit(1 if failures else 0)
