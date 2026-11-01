# SPDX-License-Identifier: 0BSD
extends SceneTree
const LIBRARY=preload("res://addons/characters/runtime/assets/Zombie.sleepers.res")
var checks:=0
var failures:=0
var report:Array=[]
var folder:="res://reports/zombie_sleepers"

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)

func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--sleeper-output="):folder=argument.trim_prefix("--sleeper-output=")
	run.call_deferred()

func poses(zombie:Node3D)->Array[Transform3D]:
	var result:Array[Transform3D]=[]
	for bone in zombie.skeleton.get_bone_count():result.append(zombie.skeleton.get_bone_global_pose(bone))
	return result

func difference(first:Array[Transform3D],second:Array[Transform3D])->float:
	var error:=0.0
	for bone in first.size():
		error=maxf(error,first[bone].origin.distance_to(second[bone].origin))
		for axis in 3:error=maxf(error,first[bone].basis[axis].distance_to(second[bone].basis[axis]))
	return error

func run()->void:
	var zombie:=preload("res://addons/characters/runtime/zombie.gd").new()
	root.add_child(zombie);zombie.set_physics_process(false);zombie.set_behavior(false)
	zombie.animation_player.add_animation_library("sleepers",LIBRARY)
	check(zombie.initialized and zombie.skeleton.get_bone_count()==59,"original live R4 rig admits six additional sleeper clips")
	var expected:={"Zombie_Sleep_Seated":4.,"Zombie_Sleep_Lying":4.,"Zombie_Wake_Seated":3.2,"Zombie_Wake_Lying":4.2,"Zombie_Wake_Seated_Crawl":2.8,"Zombie_Wake_Lying_Crawl":2.6}
	check(LIBRARY.get_animation_list().size()==expected.size(),"only the six declared sleeper animations are distributed")
	var idle:={}
	for name:String in ["Zombie_Idle","Zombie_Crawl_Idle"]:
		zombie.play_clip(name);zombie.animation_player.advance(0)
		idle[name]=poses(zombie)
	var beginnings:={}
	for clip:String in LIBRARY.get_animation_list():
		var animation:=LIBRARY.get_animation(clip)
		var looping:=animation.loop_mode
		var sleeping:=clip.begins_with("Zombie_Sleep_")
		check(is_equal_approx(animation.length,expected[clip]) and looping==(Animation.LOOP_LINEAR if sleeping else Animation.LOOP_NONE),clip+": duration and loop contract")
		var safe_tracks:=true
		var morphs:=0
		for track in animation.get_track_count():
			var kind:=animation.track_get_type(track)
			safe_tracks=safe_tracks and kind in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D,Animation.TYPE_BLEND_SHAPE]
			if kind==Animation.TYPE_BLEND_SHAPE:
				morphs+=1
				for key in animation.track_get_key_count(track):safe_tracks=safe_tracks and is_zero_approx(animation.track_get_key_value(track,key))
		check(safe_tracks and morphs==7,clip+": pose-only tracks reset all seven inherited morphs")
		animation.loop_mode=Animation.LOOP_NONE
		zombie.play_clip(clip);zombie.animation_player.advance(0)
		var first:=poses(zombie)
		beginnings[clip]=first
		var previous:=first
		var root_bone:int=zombie.skeleton.find_bone("Root")
		var root_still:=true
		var finite:=true
		var max_step:=0.0
		var min_skin:=INF
		var envelope_valid:=true
		var native_bounds_valid:=true
		var envelopes:PackedVector3Array=animation.get_meta("skin_envelopes",PackedVector3Array())
		var sample_count:=int(round(animation.length*60))+1
		check(envelopes.size()==2*(int((sample_count-1)/5)+1) and animation.get_meta("envelope_hz",0)==12.0,clip+": compact pre-baked 12 Hz clearance envelopes")
		for frame in sample_count:
			zombie.animation_player.seek(minf(frame/60.0,animation.length),true);zombie.animation_player.advance(0)
			var current:=poses(zombie)
			root_still=root_still and current[root_bone].is_equal_approx(first[root_bone])
			for bone in current.size():
				finite=finite and current[bone].is_finite()
				max_step=maxf(max_step,current[bone].origin.distance_to(previous[bone].origin))
			var slot:=int(frame/5)*2
			var envelope:=AABB(envelopes[slot],envelopes[slot+1]) if slot+1<envelopes.size() else AABB()
			for part:String in zombie.PARTS:
				var bounds:AABB=zombie.anatomy.sample_bounds(part,Transform3D.IDENTITY)
				min_skin=minf(min_skin,bounds.position.y)
				envelope_valid=envelope_valid and envelope.encloses(bounds)
				if frame in [0,int(sample_count/2),sample_count-1]:
					var vertices:PackedVector3Array=zombie.anatomy.sample_vertices(part,Transform3D.IDENTITY)
					for vertex in vertices:native_bounds_valid=native_bounds_valid and bounds.grow(.00001).has_point(vertex)
			previous=current
		check(finite and root_still,clip+": finite poses without root-motion or world translation")
		check(max_step<.08,clip+": no single-frame bone-position snap ("+str(max_step)+" m)")
		check(min_skin>=-.005,clip+": every rendered limb stays above flat-floor tolerance ("+str(min_skin)+" m)")
		check(envelope_valid and native_bounds_valid,clip+": native skin bounds and baked envelopes contain actual vertices")
		if sleeping:
			check(difference(first,previous)<.0001,clip+": breathing loop closes without a pose seam")
		else:
			var exit_name:="Zombie_Crawl_Idle" if clip.ends_with("_Crawl") else "Zombie_Idle"
			check(difference(idle[exit_name],previous)<.0001,clip+": exit exactly matches original "+exit_name)
		animation.loop_mode=looping
		report.append({"clip":clip,"frames":sample_count,"minimum_skin_y":min_skin,"max_bone_step":max_step,"baked_envelope_count":envelopes.size()/2})
	for clip:String in expected:
		if clip.begins_with("Zombie_Sleep_"):continue
		var pose:="Seated" if clip.contains("Seated") else "Lying"
		check(difference(beginnings["Zombie_Sleep_"+pose],beginnings[clip])<.0001,clip+": starts exactly from its sleeping pose")
	check(zombie.anatomy.sample_bounds("unknown",Transform3D.IDENTITY)==AABB(),"invalid region returns no skin bounds")
	check(zombie.anatomy.sample_bounds("head",Transform3D(Basis.IDENTITY,Vector3.INF))==AABB(),"nonfinite transforms return no skin bounds")
	var transformed:=Transform3D(Basis(Vector3.UP,.7),Vector3(3,2,-4))
	var transformed_bounds:AABB=zombie.anatomy.sample_bounds("head",transformed)
	var transformed_valid:=true
	for vertex in zombie.anatomy.sample_vertices("head",transformed):transformed_valid=transformed_valid and transformed_bounds.grow(.00001).has_point(vertex)
	check(transformed_valid and transformed_bounds.size.length()>.1,"native bounds preserve transformed skin-space coordinates")
	zombie.free()
	var error:=DirAccess.make_dir_recursive_absolute(folder)
	var output:=FileAccess.open(folder.path_join("pose_checks.json"),FileAccess.WRITE) if error==OK else null
	if output==null:
		failures+=1;push_error("Sleeper pose report destination is not writable")
	else:output.store_string(JSON.stringify({"checks":checks,"failures":failures,"clips":report},"  "))
	print("ZOMBIE_SLEEPERS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
