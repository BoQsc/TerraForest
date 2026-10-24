# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var rows:Array=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func pose(view:Node3D,clip:String,time:float)->void:
	view.animation_player.play(view.clips[clip],0)
	view.animation_player.seek(time,true);view.animation_player.pause();view.animation_player.advance(0)
func tool_head(mesh:MeshInstance3D,skeleton:Skeleton3D,working_point:bool=false)->Vector3:
	# Evaluate the actual steel mesh using its bind map, rather than assuming
	# exported bone axes or counting a bone's origin as the pick's head.
	var total:=Vector3.ZERO;var count:=0
	for surface in mesh.mesh.get_surface_count():
		var material:Material=mesh.mesh.surface_get_material(surface)
		if not ("Ground cutting steel" if working_point else "Forged carbon steel") in material.resource_name:continue
		var arrays:=mesh.mesh.surface_get_arrays(surface)
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
		var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
		var influences:=bones.size()/vertices.size()
		var minimum_x:=INF
		if working_point:
			for vertex in vertices:minimum_x=minf(minimum_x,vertex.x)
		for vertex in vertices.size():
			if working_point and vertices[vertex].x>minimum_x+.00001:continue
			var current:=Vector3.ZERO
			for influence in influences:
				var offset:=vertex*influences+influence;var bind:int=bones[offset]
				if weights[offset]<=0:continue
				var name:=mesh.skin.get_bind_name(bind)
				var index:=skeleton.find_bone(name) if name!=&"" else mesh.skin.get_bind_bone(bind)
				current+=(skeleton.get_bone_global_pose(index)*mesh.skin.get_bind_pose(bind)*vertices[vertex])*weights[offset]
			total+=skeleton.global_transform*current;count+=1
	return total/maxi(count,1)
func run()->void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"actual temporary world becomes ready")
	if game.loading_active:game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();quit(1);return
	game.set_physics_process(false);game._clear_motion();game.zombies.clear();game.session_menu.set_open(false)
	var view:Node3D=game.tool_view.human;view.pickaxe_swing="diagonal";view.set_process(false);game.player_hud.equip(0)
	check(view.body==game.player and view.active_clip=="FP_Pickaxe_Diagonal_Idle","real belt selects the diagonal hold on the existing player body")
	check(view.clips.has_all(["FP_Pickaxe_Swing","FP_Place_Relaxed","FP_Pickaxe_Fresh_Swing","FP_Pickaxe_SidePullback_Swing"]),"original clips, placement and pickaxe alternatives coexist with the fixed-grip default")
	var animation:Animation=view.animation_player.get_animation(view.clips.FP_Pickaxe_Diagonal_Swing)
	check(is_equal_approx(animation.length,1.2) and animation.loop_mode==Animation.LOOP_NONE,"diagonal strike is a 1.2-second one-shot matching the melee cooldown")
	var animation_only:=true
	for track in animation.get_track_count():animation_only=animation_only and animation.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D,Animation.TYPE_BLEND_SHAPE]
	check(animation_only,"new animation has no gameplay, audio or method events")
	var skeleton:Skeleton3D=view.model.find_child("Skeleton3D",true,false)
	var pick:MeshInstance3D=view.model.find_child("Equipment_Pickaxe",true,false)
	var root_index:=skeleton.find_bone("Root");var weapon:=skeleton.find_bone("Weapon_Pickaxe")
	var left:=skeleton.find_bone("LeftHand");var right:=skeleton.find_bone("RightHand")
	pose(view,"FP_Pickaxe_Diagonal_Idle",0)
	var left_ready:Vector3=game.camera.global_transform.affine_inverse()*skeleton.global_transform*skeleton.get_bone_global_pose(left).origin
	var right_ready:Vector3=game.camera.global_transform.affine_inverse()*skeleton.global_transform*skeleton.get_bone_global_pose(right).origin
	var handle_axis:Vector3=(tool_head(pick,skeleton)-skeleton.global_transform*skeleton.get_bone_global_pose(weapon).origin).normalized()
	var hand_separation:float=(skeleton.global_transform.basis*(skeleton.get_bone_global_pose(right).origin-skeleton.get_bone_global_pose(left).origin)).dot(handle_axis)
	check(right_ready.y>left_ready.y and hand_separation>.15,"right hand holds above the left, at the upper handle station")
	var folder:="res://reports/pickaxe_diagonal";DirAccess.make_dir_recursive_absolute(folder)
	var start:Array[Transform3D]=[]
	var root_pose:Transform3D;var left_grip:Transform3D;var right_grip:Transform3D
	var root_static:=true;var stable_grip:=true;var seam:=0.0
	var previous_depth:=-INF;var forward_motion:=true;var stays_right:=true;var stays_angled:=true
	var sample_points:={}
	for frame in 73:
		pose(view,"FP_Pickaxe_Diagonal_Swing",float(frame)/60)
		var tool:Transform3D=skeleton.get_bone_global_pose(weapon)
		var current_left:Transform3D=tool.affine_inverse()*skeleton.get_bone_global_pose(left)
		var current_right:Transform3D=tool.affine_inverse()*skeleton.get_bone_global_pose(right)
		if frame==0:
			root_pose=skeleton.get_bone_global_pose(root_index);left_grip=current_left;right_grip=current_right
			for index in skeleton.get_bone_count():start.append(skeleton.get_bone_pose(index))
		root_static=root_static and root_pose.is_equal_approx(skeleton.get_bone_global_pose(root_index))
		stable_grip=stable_grip and current_left.is_equal_approx(left_grip) and current_right.is_equal_approx(right_grip)
		var head:=tool_head(pick,skeleton)
		var screen:Vector2=game.camera.unproject_position(head)
		var camera_inverse:Transform3D=game.camera.global_transform.affine_inverse()
		var point_world:=tool_head(pick,skeleton,true)
		var point:Vector3=camera_inverse*point_world
		var handle:Vector3=camera_inverse*skeleton.global_transform*tool.origin
		var current_head:Vector3=camera_inverse*head
		var right_hand:Vector3=camera_inverse*skeleton.global_transform*skeleton.get_bone_global_pose(right).origin
		var shaft_angle:=rad_to_deg(atan2(handle.x-current_head.x,current_head.y-handle.y))
		if frame>=20 and frame<=38:
			forward_motion=forward_motion and -point.z>=previous_depth-.002;previous_depth=-point.z
		if frame>=32 and frame<=43:
			stays_right=stays_right and handle.x>.14 and right_hand.x>.13 and point.x>.05 and point.x<.22 and current_head.x>.05
			stays_angled=stays_angled and shaft_angle>3 and shaft_angle<12
		if frame in [0,20,32,38,43,72]:
			sample_points[frame]=point
			rows.append({"frame":frame,"head_world":head,"head_screen":screen,"working_point_camera":[point.x,point.y,point.z],"handle_camera":[handle.x,handle.y,handle.z],"shaft_angle_degrees":shaft_angle})
		if frame in [0,20,32,38,43] and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder+"/world_%02d.png"%frame)
		if frame==72:
			for index in skeleton.get_bone_count():
				var end:Transform3D=skeleton.get_bone_pose(index)
				seam=maxf(seam,(end.origin-start[index].origin).length())
				for axis in 3:seam=maxf(seam,(end.basis[axis]-start[index].basis[axis]).length())
	check(root_static,"animation leaves the physical player's root in place")
	check(stable_grip,"both fitted hand transforms remain attached to the handle throughout the swing")
	var chamber:Vector3=sample_points[20];var contact:Vector3=sample_points[32];var follow:Vector3=sample_points[38]
	check(forward_motion and chamber.z-contact.z>.25,"actual sharpened point drives forward at least 25 cm from the right-side wind-up")
	check(chamber.x-contact.x>.25 and contact.x>.05 and contact.x<.22 and absf(contact.y)<.06 and -contact.z>.95,"forward contact stays slightly right of the aim line, approached diagonally from the right")
	check(stays_right,"hands and handle stay to the right through contact and follow-through")
	check(stays_angled,"left shaft roll stays restrained below 12 degrees through contact and follow-through")
	check(follow.x<contact.x and follow.x>-.03 and contact.y-follow.y>.02 and contact.y-follow.y<.15,"short left/down follow-through remains in front of the player")
	check(seam<.0001,"strike ends at its starting ready pose without a bone-pose pop")
	view.equip(1);view.swing();var remaining:float=view.action_remaining;view.swing()
	check(view.active_clip=="FP_Pickaxe_Diagonal_Swing" and is_equal_approx(remaining,view.action_remaining),"held input cannot restart an unfinished diagonal strike")
	view.hide();view._process(.25)
	check(is_equal_approx(view.action_remaining,remaining),"hidden presentation suspends the action timer")
	view.show();view.set_process(true);await create_timer(1.5).timeout;view.set_process(false)
	check(view.active_clip=="FP_Pickaxe_Diagonal_Idle" and view.action_remaining==0,"live one-shot playback returns to the diagonal ready hold")
	game.player.velocity=Vector3(3,0,0);view._process(.01)
	check(view.active_clip=="FP_Pickaxe_Diagonal_Walk","walking keeps the new diagonal hold")
	game.player.velocity=Vector3(6,0,0);view._process(.01)
	check(view.active_clip=="FP_Pickaxe_Diagonal_Run","running keeps the new diagonal hold")
	game.player.velocity=Vector3.ZERO;view.swing();view.equip(2)
	check(view.active_clip=="FP_Axe_Idle" and view.action_remaining==0,"tool switching cancels the strike and preserves the axe hold")
	view.equip(1);check(view.place(),"existing placement action can temporarily free the equipped hand")
	view._process(1.0)
	check(not view.placement_active and pick.visible and view.active_clip=="FP_Pickaxe_Diagonal_Idle","placement restores the new pickaxe grip")
	view.equip(0);view._process(.1)
	check(view.active_clip=="FP_Unarmed_Idle","empty hands retain their existing idle pose")
	FileAccess.open(folder+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"approval":"PENDING USER VISUAL REVIEW; do not commit","checks":checks,"failures":failures,"head_samples":rows,"seam_error":seam,"ready_vertical_hand_gap_m":right_ready.y-left_ready.y,"hand_station_separation_m":hand_separation,"scope":"Actual temporary world, real equipment/view controller and evaluated steel head. Animation engineering checks do not approve its appearance or qualify world performance."},"  "))
	game.shutdown_requested=true;game.terrain.backend.disable_snapshot_writes();await game.terrain.shutdown_after_edits();game.free()
	print("PICKAXE_DIAGONAL checks=",checks," failures=",failures);quit(1 if failures else 0)
