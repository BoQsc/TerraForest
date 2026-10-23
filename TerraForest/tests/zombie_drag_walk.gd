# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
var encounters:Node3D
var active:=false
var target:Node3D
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func tick()->void:
	if active:encounters.update(1.0/60,Vector3.ZERO,true)
func minimum_sole(zombie:Node3D,part:String)->float:
	var mesh:ArrayMesh=zombie._bake_cpu(zombie.part_meshes[part],zombie.global_transform.affine_inverse())
	var low:=INF
	for surface in mesh.get_surface_count():
		var vertices:PackedVector3Array=mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:low=minf(low,vertex.y)
	return low
func run()->void:
	var stage:=Node3D.new();root.add_child(stage)
	var ground:=StaticBody3D.new();stage.add_child(ground)
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(60,1,60);collision.shape=box;collision.position.y=-.5;ground.add_child(collision)
	target=preload("res://addons/characters/runtime/zombie_target.gd").new();stage.add_child(target);target.position=Vector3(0,0,8)
	encounters=preload("res://addons/characters/runtime/zombie_world.gd").new();stage.add_child(encounters)
	encounters.enabled=true;encounters.target=target;encounters.readiness=func(_b:AABB):return true
	await physics_frame;await physics_frame
	var zombie:CharacterBody3D=encounters.spawn_at(Vector3.ZERO)
	check(zombie!=null and zombie.initialized and zombie._r4_enabled,"real encounter controller admits the original R4 rig")
	if zombie==null:stage.free();quit(1);return
	zombie.set_physics_process(false);zombie.set_behavior(false)
	var key:String=zombie._animation_key("Zombie_Walk_Drag_Right")
	check(not key.is_empty() and zombie.animation_player.get_animation_list().size()==16,"all 15 original actions coexist with the new dragging walk")
	var animation:Animation=zombie.animation_player.get_animation(key)
	check(is_equal_approx(animation.length,2.0) and animation.loop_mode==Animation.LOOP_LINEAR,"dragging walk is a looping two-second action")
	check(is_equal_approx(zombie.walk_speed,.45) and is_equal_approx(zombie._standing_walk_reference_speed(),.45),"body speed matches the authored slow 0.45-m/s gait")
	var bone_or_shape_only:=true
	for track in animation.get_track_count():bone_or_shape_only=bone_or_shape_only and animation.track_get_type(track) in [Animation.TYPE_POSITION_3D,Animation.TYPE_ROTATION_3D,Animation.TYPE_SCALE_3D,Animation.TYPE_BLEND_SHAPE]
	check(bone_or_shape_only,"animation cannot invoke movement or world mutation")
	var root_bone:int=zombie.skeleton.find_bone("Root")
	var root_pose:Transform3D
	var root_static:=true
	var left_min:=INF;var left_max:=-INF;var right_min:=INF;var right_max:=-INF
	var seam:Array[Transform3D]=[]
	var seam_error:=0.0
	var stance_start:=0.0;var stance_end:=0.0
	var rows:Array=[]
	animation.loop_mode=Animation.LOOP_NONE
	zombie._play_animation("Zombie_Walk_Drag_Right",true)
	for frame in 121:
		zombie.animation_player.seek(float(frame)/60,true);zombie.animation_player.advance(0)
		var current_root:Transform3D=zombie.skeleton.get_bone_global_pose(root_bone)
		if frame==0:
			root_pose=current_root
			for bone in zombie.skeleton.get_bone_count():seam.append(zombie.skeleton.get_bone_pose(bone))
		root_static=root_static and current_root.is_equal_approx(root_pose)
		var l:=minimum_sole(zombie,"foot_l");var r:=minimum_sole(zombie,"foot_r")
		var planted_z:float=zombie.skeleton.get_bone_global_pose(zombie.skeleton.find_bone("LeftFoot")).origin.z+.45*float(frame)/60.0
		if frame==12:stance_start=planted_z
		if frame==48:stance_end=planted_z
		left_min=minf(left_min,l);left_max=maxf(left_max,l);right_min=minf(right_min,r);right_max=maxf(right_max,r)
		if frame%10==0:rows.append({"frame":frame,"left_sole_y":l,"right_sole_y":r})
		if frame==120:
			for bone in zombie.skeleton.get_bone_count():
				var pose:Transform3D=zombie.skeleton.get_bone_pose(bone)
				seam_error=maxf(seam_error,(pose.origin-seam[bone].origin).length())
				for axis in 3:seam_error=maxf(seam_error,(pose.basis[axis]-seam[bone].basis[axis]).length())
	animation.loop_mode=Animation.LOOP_LINEAR
	check(root_static,"root stays in place throughout the animation")
	check(seam_error<.0001,"all 59 bone poses join without a loop pop")
	check(left_min>=-.003 and right_min>=-.003,"evaluated boot surfaces remain above the flat floor")
	check(left_max>.09 and right_max<.012,"left foot steps while the right toe stays close enough to drag")
	check(absf(stance_end-stance_start)<.01,"supporting foot stays planted during the authored travel-speed stance")
	zombie.dragging_walk=false;check(zombie._standing_walk_clip()=="Zombie_Walk","preserved original walk remains selectable")
	zombie.dragging_walk=true
	zombie.position=Vector3(0,.06,0);zombie.set_behavior(true);zombie.set_physics_process(true)
	physics_frame.connect(tick);active=true
	var observed:=false;var peak_work:=0
	for frame in 360:
		await physics_frame
		observed=observed or String(zombie._current_clip).ends_with("Zombie_Walk_Drag_Right")
		peak_work=maxi(peak_work,int(encounters.navigation_status.get("route_work",0)))
	check(observed and zombie.position.z>1.5,"actual native navigation and body motor use the dragging walk while pursuing")
	check(absf(zombie.animation_player.speed_scale-1.0)<.05,"default healthy walking keeps the authored slow cadence")
	var suspended:Vector3=zombie.position
	active=false;encounters.update(.01,Vector3.ZERO,false)
	for frame in 10:await physics_frame
	check(zombie.position.is_equal_approx(suspended),"suspension holds the body and gait")
	encounters.update(.01,Vector3.ZERO,true);active=true
	target.position=zombie.position+Vector3(0,0,.7)
	for frame in 180:
		await physics_frame
		if target.damage_received>0:break
	check(target.damage_received>0,"dragging locomotion still transitions into authored attack contact")
	active=false;zombie.set_behavior(false)
	zombie.receive_hit("shin_r",100,zombie.position+Vector3.UP*.4,Vector3.ZERO)
	for frame in 60:await physics_frame
	zombie.play_clip("Zombie_Walk_Drag_Right")
	check(zombie._crawling and zombie._manual_clip=="Zombie_Crawl","severed leg still selects crawling instead of a missing-leg standing gait")
	DirAccess.make_dir_recursive_absolute("res://reports/zombie_drag_walk")
	FileAccess.open("res://reports/zombie_drag_walk/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"left_sole_min":left_min,"left_sole_max":left_max,"right_sole_min":right_min,"right_sole_max":right_max,"stance_drift_m":absf(stance_end-stance_start),"seam_error":seam_error,"samples":rows,"native_peak_work":peak_work,"scope":"Flat-floor evaluated skin and live shared-navigation controller lifecycle; no terrain foot IK or complete-world traversal claim."},"  "))
	encounters.clear();await process_frame;stage.free();await process_frame
	print("ZOMBIE_DRAG_WALK checks=",checks," failures=",failures);quit(1 if failures else 0)
