# SPDX-License-Identifier: 0BSD
extends SceneTree
const MODEL=preload("res://addons/characters/runtime/assets/Zombie.r4.glb")

func find_type(node:Node,type:String)->Node:
	if node.is_class(type):return node
	for child in node.get_children():
		var found:=find_type(child,type)
		if found!=null:return found
	return null

func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()

func run()->void:
	var document:=GLTFDocument.new()
	var state:=GLTFState.new()
	if document.append_from_file("res://addons/characters/authoring/Zombie.sleepers.glb",state)!=OK:
		push_error("Sleeper animation GLB rejected");quit(1);return
	var imported:=document.generate_scene(state,60.0,false,false)
	var original:=MODEL.instantiate()
	root.add_child(imported);root.add_child(original)
	var source:=find_type(imported,"AnimationPlayer") as AnimationPlayer
	var target:=find_type(original,"AnimationPlayer") as AnimationPlayer
	var source_skeleton:=find_type(imported,"Skeleton3D") as Skeleton3D
	var target_skeleton:=find_type(original,"Skeleton3D") as Skeleton3D
	if source==null or target==null or source_skeleton==null or target_skeleton==null:
		push_error("Sleeper animation rig missing");quit(1);return
	var rest_error:=0.0
	for bone in source_skeleton.get_bone_count():
		var target_bone:=target_skeleton.find_bone(source_skeleton.get_bone_name(bone))
		if target_bone<0:push_error("Sleeper rig bone absent in R4");quit(1);return
		var difference:Transform3D=source_skeleton.get_bone_global_rest(bone).affine_inverse()*target_skeleton.get_bone_global_rest(target_bone)
		rest_error=maxf(rest_error,difference.origin.length())
		for axis in 3:rest_error=maxf(rest_error,(difference.basis[axis]-Basis.IDENTITY[axis]).length())
	if source_skeleton.get_bone_count()!=59 or rest_error>.0001:
		push_error("Sleeper bind pose differs: "+str(rest_error));quit(1);return
	var neutral:Animation
	for name in target.get_animation_list():
		if String(name).ends_with("Zombie_Walk"):neutral=target.get_animation(name)
	if neutral==null:push_error("R4 neutral morph reference absent");quit(1);return
	var library:=AnimationLibrary.new()
	var skeleton_path:=String(target.get_node(target.root_node).get_path_to(target_skeleton))
	var rows:Array=[]
	for name in source.get_animation_list():
		var clip_name:=String(name).get_file()
		if not clip_name.begins_with("Zombie_Sleep_") and not clip_name.begins_with("Zombie_Wake_"):continue
		var animation:=source.get_animation(name).duplicate(true) as Animation
		for track in range(animation.get_track_count()-1,-1,-1):
			var path:=animation.track_get_path(track)
			if path.get_subname_count()!=1 or target_skeleton.find_bone(path.get_subname(0))<0:
				animation.remove_track(track);continue
			animation.track_set_path(track,NodePath(skeleton_path+":"+path.get_subname(0)))
		for track in neutral.get_track_count():
			if neutral.track_get_type(track)!=Animation.TYPE_BLEND_SHAPE:continue
			var added:=animation.add_track(Animation.TYPE_BLEND_SHAPE)
			animation.track_set_path(added,neutral.track_get_path(track))
			animation.track_insert_key(added,0.0,0.0)
			animation.track_insert_key(added,animation.length,0.0)
		animation.resource_name=clip_name
		animation.loop_mode=Animation.LOOP_LINEAR if clip_name.begins_with("Zombie_Sleep_") else Animation.LOOP_NONE
		var original_keys:=0
		for track in animation.get_track_count():original_keys+=animation.track_get_key_count(track)
		animation.optimize(.0002,.0002,5)
		var optimized_keys:=0
		for track in animation.get_track_count():optimized_keys+=animation.track_get_key_count(track)
		library.add_animation(clip_name,animation)
		rows.append({"name":clip_name,"seconds":animation.length,"tracks":animation.get_track_count(),"loop":animation.loop_mode,"original_keys":original_keys,"optimized_keys":optimized_keys})
	if rows.size()!=6:push_error("Expected all six sleeper clips, got "+str(rows.size()));quit(1);return
	var zombie:=preload("res://addons/characters/runtime/zombie.gd").new()
	root.add_child(zombie);zombie.set_physics_process(false);zombie.set_behavior(false)
	zombie.animation_player.add_animation_library("sleepers",library)
	var skin_rows:Array=[]
	for clip:String in library.get_animation_list():
		var animation:Animation=library.get_animation(clip)
		var loop:=animation.loop_mode
		animation.loop_mode=Animation.LOOP_NONE
		zombie.play_clip(clip)
		var envelopes:Array[AABB]=[]
		var samples:Array=[]
		var frames:=int(round(animation.length*60))
		for frame in frames+1:
			zombie.animation_player.seek(minf(float(frame)/60,animation.length),true);zombie.animation_player.advance(0)
			zombie.skeleton.force_update_all_bone_transforms()
			var bounds:=AABB()
			var parts:={}
			for part:String in zombie.PARTS:
				var region:AABB=zombie.anatomy.sample_bounds(part,zombie.global_transform.affine_inverse())
				bounds=region if bounds.size==Vector3.ZERO else bounds.merge(region)
				parts[part]=region.position.y
			var slot:=frame/5
			if slot>=envelopes.size():envelopes.append(bounds)
			else:envelopes[slot]=envelopes[slot].merge(bounds)
			samples.append({"frame":frame,"low":bounds.position.y,"high":bounds.end.y,"parts_low":parts})
		var packed:=PackedVector3Array()
		for envelope in envelopes:
			var padded:=envelope.grow(.015)
			packed.append(padded.position);packed.append(padded.size)
		animation.set_meta("skin_envelopes",packed)
		animation.set_meta("envelope_hz",12.0)
		animation.set_meta("envelope_source_hz",60.0)
		animation.loop_mode=loop
		skin_rows.append({"name":clip,"samples":samples})
	zombie.free()
	var error:=ResourceSaver.save(library,"res://addons/characters/runtime/assets/Zombie.sleepers.res",ResourceSaver.FLAG_COMPRESS)
	DirAccess.make_dir_recursive_absolute("res://reports/zombie_sleepers")
	FileAccess.open("res://reports/zombie_sleepers/import.json",FileAccess.WRITE).store_string(JSON.stringify({"rest_error":rest_error,"clips":rows,"save_error":error},"  "))
	FileAccess.open("res://reports/zombie_sleepers/skin_samples.json",FileAccess.WRITE).store_string(JSON.stringify(skin_rows,"  "))
	print("ZOMBIE_SLEEPERS_IMPORT ",JSON.stringify(rows))
	imported.free();original.free();quit(0 if error==OK else 1)
