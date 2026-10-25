extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var model:Node3D=load("res://addons/characters/runtime/assets/Human.r11.glb").instantiate();root.add_child(model)
	var skeleton:Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
	var player:AnimationPlayer=model.find_children("*","AnimationPlayer",true,false)[0]
	var library:=AnimationLibrary.new()
	for source:String in ["Crouch","Pickaxe_RightGrip_Crouch"]:
		player.play(source);player.advance(0);skeleton.force_update_all_bone_transforms()
		var original:Array[Transform3D]=[]
		for bone in skeleton.get_bone_count():original.append(skeleton.get_bone_global_pose(bone))
		var hips:int=skeleton.find_bone("Hips");var lowered:Transform3D=original[hips];lowered.origin+=Vector3(0,-.7,-.1);skeleton.set_bone_global_pose(hips,lowered)
		skeleton.force_update_all_bone_transforms()
		for side:String in ["Left","Right"]:
			var thigh:int=skeleton.find_bone(side+"UpLeg");var shin:int=skeleton.find_bone(side+"Leg");var foot:int=skeleton.find_bone(side+"Foot")
			var hip:Vector3=skeleton.get_bone_global_pose(thigh).origin
			var ankle:Vector3=original[foot].origin
			var upper:float=original[thigh].origin.distance_to(original[shin].origin)
			var lower:float=original[shin].origin.distance_to(ankle)
			var axis:Vector3=(ankle-hip).normalized();var distance:float=clampf(hip.distance_to(ankle),.001,upper+lower-.001)
			var along:float=(upper*upper-lower*lower+distance*distance)/(2*distance)
			var bend:Vector3=(Vector3.BACK-axis*axis.dot(Vector3.BACK)).normalized()
			var knee:Vector3=hip+axis*along+bend*sqrt(maxf(0,upper*upper-along*along))
			var thigh_rotation:=Quaternion((original[shin].origin-original[thigh].origin).normalized(),(knee-hip).normalized())
			var shin_rotation:=Quaternion((original[foot].origin-original[shin].origin).normalized(),(ankle-knee).normalized())
			skeleton.set_bone_global_pose(thigh,Transform3D(Basis(thigh_rotation)*original[thigh].basis,hip));skeleton.force_update_all_bone_transforms()
			skeleton.set_bone_global_pose(shin,Transform3D(Basis(shin_rotation)*original[shin].basis,knee));skeleton.force_update_all_bone_transforms()
			skeleton.set_bone_global_pose(foot,original[foot]);skeleton.force_update_all_bone_transforms()
		for bone in skeleton.get_bone_count():
			if not String(skeleton.get_bone_name(bone)).begins_with("Weapon_"):continue
			var ancestor:int=skeleton.get_bone_parent(bone)
			while ancestor>=0 and ancestor!=hips:ancestor=skeleton.get_bone_parent(ancestor)
			if ancestor<0:
				var weapon:Transform3D=original[bone];weapon.origin+=lowered.origin-original[hips].origin;skeleton.set_bone_global_pose(bone,weapon);skeleton.force_update_all_bone_transforms()
		var animation:=Animation.new();animation.length=1;animation.loop_mode=Animation.LOOP_LINEAR
		for bone in skeleton.get_bone_count():
			var bone_name:String=skeleton.get_bone_name(bone);var pose:Transform3D=skeleton.get_bone_pose(bone)
			var path:=NodePath(str(player.get_node(player.root_node).get_path_to(skeleton))+":"+bone_name)
			var position_track:=animation.add_track(Animation.TYPE_POSITION_3D);animation.track_set_path(position_track,path);animation.position_track_insert_key(position_track,0,pose.origin)
			var rotation_track:=animation.add_track(Animation.TYPE_ROTATION_3D);animation.track_set_path(rotation_track,path);animation.rotation_track_insert_key(rotation_track,0,pose.basis.get_rotation_quaternion())
			var scale_track:=animation.add_track(Animation.TYPE_SCALE_3D);animation.track_set_path(scale_track,path);animation.scale_track_insert_key(scale_track,0,pose.basis.get_scale())
		library.add_animation("Player_Pickaxe_Crouch" if source.begins_with("Pickaxe") else "Player_Crouch",animation)
		print("CROUCH_BAKE ",source," hip_drop=",original[hips].origin.y-skeleton.get_bone_global_pose(hips).origin.y," left_ankle_error=",original[skeleton.find_bone("LeftFoot")].origin.distance_to(skeleton.get_bone_global_pose(skeleton.find_bone("LeftFoot")).origin))
	var error:=ResourceSaver.save(library,"res://addons/characters/runtime/assets/Human.crouch.res")
	model.free();print("PLAYER_CROUCH_BAKE error=",error);quit(0 if error==OK else 1)
