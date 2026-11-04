# SPDX-License-Identifier: 0BSD
extends "res://tools/preview_item_use.gd"
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",message)
func difference(a:Transform3D,b:Transform3D)->float:
	var result:=a.origin.distance_to(b.origin)
	for axis in 3:result=maxf(result,(a.basis[axis]-b.basis[axis]).length())
	return result
func run()->void:
	var production:=preload("res://addons/characters/runtime/human_view.gd").new();root.add_child(production)
	check(production.clips.has("FP_Item_Hold") and FileAccess.get_sha256("res://addons/characters/runtime/assets/Human.item_hold.res")==FileAccess.get_sha256(CANDIDATE),"integrated baseline retains the reviewed animation data unchanged")
	production.free()
	item_library=load(CANDIDATE)
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://addons/characters/authoring/Human.item_use.json"));hand_samples=source.support_samples_hand
	check(item_library.get_animation_list().size()==3,"candidate contains hold, equip and use only")
	var data:=setup("fresh");var view:Node3D=data.view;var skeleton:Skeleton3D=data.skeleton
	pose(view,"FP_Item_Hold",0)
	var ready:Array[Transform3D]=[];var finger_pose:={}
	for bone in skeleton.get_bone_count():
		ready.append(skeleton.get_bone_pose(bone))
		if String(skeleton.get_bone_name(bone)).begins_with("RightHand") and skeleton.get_bone_name(bone)!="RightHand":finger_pose[bone]=skeleton.get_bone_pose(bone)
	var skin:Skin=view.body_mesh.skin;var bindings:Array[int]=[]
	for index in skin.get_bind_count():
		var name:=String(skin.get_bind_name(index));bindings.append(skeleton.find_bone(name) if not name.is_empty() else skin.get_bind_bone(index))
	var vertices:Array[Dictionary]=[]
	for surface in view.body_mesh.mesh.get_surface_count():
		var arrays:Array=view.body_mesh.mesh.surface_get_arrays(surface)
		var width:int=arrays[Mesh.ARRAY_WEIGHTS].size()/arrays[Mesh.ARRAY_VERTEX].size()
		for vertex in arrays[Mesh.ARRAY_VERTEX].size():
			var indices:Array[int]=[];var weights:Array[float]=[];var hand_weight:=0.0
			for slot in width:
				var binding:int=arrays[Mesh.ARRAY_BONES][vertex*width+slot];var weight:float=arrays[Mesh.ARRAY_WEIGHTS][vertex*width+slot]
				indices.append(binding);weights.append(weight)
				if String(skeleton.get_bone_name(bindings[binding])).begins_with("RightHand"):hand_weight+=weight
			if hand_weight>.8:vertices.append({"point":arrays[Mesh.ARRAY_VERTEX][vertex],"bindings":indices,"weights":weights})
	var records:={};var maximum_seam:=0.0;var sampled:=0
	for suffix:String in ["Hold","Equip","Use"]:
		var animation:=item_library.get_animation("FP_Item_"+suffix)
		check(is_equal_approx(animation.length,{"Hold":2.0,"Equip":.45,"Use":1.3}[suffix]) and animation.loop_mode==(Animation.LOOP_LINEAR if suffix=="Hold" else Animation.LOOP_NONE),suffix+": authored duration and loop policy")
		var pose_only:=true
		for track in animation.get_track_count():pose_only=pose_only and animation.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D,Animation.TYPE_BLEND_SHAPE]
		check(pose_only,suffix+": no consumption, reading reward, methods or gameplay event tracks")
		var previous:={};var wrist_bend:=0.0;var joint_step:=0.0;var minimum_drop:=INF;var body_error:=0.0;var finger_error:=0.0
		var count:=roundi(animation.length*120)
		for frame in count+1:
			pose(view,"FP_Item_"+suffix,frame/120.0);skeleton.force_update_all_bone_transforms();sampled+=1
			var hand:=skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"));var elbow:=skeleton.get_bone_global_pose(skeleton.find_bone("RightForeArm"));var shoulder:=skeleton.get_bone_global_pose(skeleton.find_bone("RightArm"))
			wrist_bend=maxf(wrist_bend,rad_to_deg((hand.origin-elbow.origin).angle_to(hand.basis.y)))
			minimum_drop=minf(minimum_drop,shoulder.origin.y-elbow.origin.y)
			for name:String in ["RightShoulder","RightArm","RightForeArm","RightHand"]:
				var index:=skeleton.find_bone(name);var q:=skeleton.get_bone_pose(index).basis.get_rotation_quaternion()
				if previous.has(name):joint_step=maxf(joint_step,rad_to_deg(q.angle_to(previous[name])))
				previous[name]=q
			for bone in skeleton.get_bone_count():
				var name:=String(skeleton.get_bone_name(bone))
				if not name.begins_with("Right"):body_error=maxf(body_error,difference(ready[bone],skeleton.get_bone_pose(bone)))
				if finger_pose.has(bone):finger_error=maxf(finger_error,difference(finger_pose[bone],skeleton.get_bone_pose(bone)))
				if frame==count or (suffix!="Equip" and frame==0):maximum_seam=maxf(maximum_seam,difference(ready[bone],skeleton.get_bone_pose(bone)))
		check(wrist_bend<5 and minimum_drop>.07,suffix+": neutral wrist and elbow below shoulder at every key/half-key")
		check(joint_step<5 and body_error<.0001,suffix+": continuous arm joints and fixed body/feet/free hand")
		check(finger_error<.0001,suffix+": relaxed cradle keeps a consistent hand shape")
		records[suffix]={"samples":count+1,"max_wrist_degrees":wrist_bend,"max_joint_half_key_degrees":joint_step,"minimum_elbow_drop_m":minimum_drop,"body_error":body_error,"finger_error":finger_error}
	check(maximum_seam<.0001,"equip end, hold loop and use endpoints join without pose jumps")
	var geometry:Array=[]
	for index in 3:
		var mesh:=item_mesh(index);mount(data,mesh)
		var minimum_clearance:=INF;var nearest_contact:=INF;var maximum_drift:=0.0;var compared:=0
		var expected:Transform3D=data.prop.transform
		for entry in [["Hold",0.0],["Equip",.225],["Use",.65]]:
			pose(view,"FP_Item_"+entry[0],entry[1]);skeleton.force_update_all_bone_transforms();data.attachment.on_skeleton_update()
			var hand_world:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))
			maximum_drift=maxf(maximum_drift,difference(expected,hand_world.affine_inverse()*data.prop.global_transform))
			var inverse:Transform3D=data.prop.global_transform.affine_inverse()*skeleton.global_transform
			var palette:Array[Transform3D]=[]
			for binding in bindings.size():palette.append(skeleton.get_bone_global_pose(bindings[binding])*skin.get_bind_pose(binding))
			var closest:=INF
			for vertex in vertices:
				var point:=Vector3.ZERO
				for slot in vertex.bindings.size():point+=(palette[vertex.bindings[slot]]*vertex.point)*vertex.weights[slot]
				point=inverse*point
				var bottom:=lower_surface(mesh,Vector2(point.x,point.z))
				if not is_finite(bottom):continue
				compared+=1;var clearance:=bottom-point.y
				minimum_clearance=minf(minimum_clearance,clearance);closest=minf(closest,absf(clearance))
			nearest_contact=maxf(nearest_contact if is_finite(nearest_contact) else 0,closest)
		check(compared>0 and minimum_clearance>-.0015 and nearest_contact<.005,"object %d: actual skinned palm clears the underside and stays in contact"%index)
		check(maximum_drift<.0001,"object %d: item follows the hand without sliding"%index)
		geometry.append({"item":index,"minimum_clearance_m":minimum_clearance,"maximum_nearest_contact_m":nearest_contact,"attachment_drift":maximum_drift,"compared_vertices":compared,"mount_height_m":mount_height(mesh)})
	var report:={"checks":checks,"failures":failures,"sampled_poses":sampled,"runtime_hand_vertices":vertices.size(),"clips":records,"maximum_seam_error":maximum_seam,"objects":geometry,"approval":"Candidate 01; player visual approval pending; review-only"}
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	FileAccess.open(OUTPUT+"/checks.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  ")+"\n")
	data.viewport.free();print("ITEM_USE_CANDIDATE ",JSON.stringify(report));quit(1 if failures else 0)
