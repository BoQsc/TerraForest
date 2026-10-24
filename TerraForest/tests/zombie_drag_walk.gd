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
func boot_vertices(zombie:Node3D,part:String,time:float)->PackedVector3Array:
	var mesh:ArrayMesh=zombie._bake_cpu(zombie.part_meshes[part],zombie.global_transform.affine_inverse())
	var result:=PackedVector3Array()
	for surface in mesh.get_surface_count():
		var vertices:PackedVector3Array=mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex in vertices:result.append(vertex+Vector3(0,0,.45*time))
	return result
func sole_indices(vertices:PackedVector3Array)->PackedInt32Array:
	var low:=INF
	for vertex in vertices:low=minf(low,vertex.y)
	var indices:=PackedInt32Array()
	for vertex in vertices.size():
		if vertices[vertex].y<low+.003:indices.append(vertex)
	return indices
func maximum_drift(a:PackedVector3Array,b:PackedVector3Array,indices:PackedInt32Array)->float:
	var value:=0.0
	for vertex in indices:value=maxf(value,a[vertex].distance_to(b[vertex]))
	return value
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
	var left_plant:=PackedVector3Array();var right_plant:=PackedVector3Array()
	var left_contacts:=PackedInt32Array();var right_contacts:=PackedInt32Array()
	var left_drift:=0.0;var right_drift:=0.0
	var pelvis_min:=Vector3(INF,INF,INF);var pelvis_max:=Vector3(-INF,-INF,-INF)
	var supported:=true
	var arm_min:=INF;var arm_max:=-INF
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
		supported=supported and minf(l,r)<.008
		var pelvis:Vector3=zombie.skeleton.get_bone_global_pose(zombie.skeleton.find_bone("Hips")).origin
		pelvis_min=pelvis_min.min(pelvis);pelvis_max=pelvis_max.max(pelvis)
		var hand:Vector3=zombie.skeleton.get_bone_global_pose(zombie.skeleton.find_bone("RightHand")).origin-pelvis
		arm_min=minf(arm_min,hand.z);arm_max=maxf(arm_max,hand.z)
		if frame==12:
			left_plant=boot_vertices(zombie,"foot_l",float(frame)/60);left_contacts=sole_indices(left_plant)
		if frame>=12 and frame<=60:left_drift=maxf(left_drift,maximum_drift(left_plant,boot_vertices(zombie,"foot_l",float(frame)/60),left_contacts))
		if frame==84:
			right_plant=boot_vertices(zombie,"foot_r",float(frame)/60);right_contacts=sole_indices(right_plant)
		if frame>=84 and frame<=114:right_drift=maxf(right_drift,maximum_drift(right_plant,boot_vertices(zombie,"foot_r",float(frame)/60),right_contacts))
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
	check(not left_contacts.is_empty() and left_drift<.002,"left boot's contact vertices hold their world position through flat support")
	check(not right_contacts.is_empty() and right_drift<.002,"weak boot's contact vertices also plant during the strong leg's recovery")
	check(supported,"at least one evaluated boot remains in contact throughout the cycle")
	check(pelvis_max.x-pelvis_min.x>.08 and pelvis_max.y-pelvis_min.y>.055,"pelvis transfers weight between feet and compresses on the weak side")
	check(arm_max-arm_min>.06,"hanging right arm follows through independently of the pelvis")
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
	# Hold the real body against a solid wall while the isolated controller
	# requests walking, then remove it. This tests collision-limited cadence;
	# autonomous navigation and route admission are checked above.
	var wall:=StaticBody3D.new();stage.add_child(wall);wall.position=Vector3(-10,1,.7)
	var wall_shape:=CollisionShape3D.new();var wall_box:=BoxShape3D.new();wall_box.size=Vector3(3,2,.1);wall_shape.shape=wall_box;wall.add_child(wall_shape)
	var blocked=preload("res://addons/characters/runtime/zombie.gd").new();stage.add_child(blocked)
	blocked.position=Vector3(-10,.01,0);target.position=Vector3(-10,0,8);blocked.target=target;blocked.set_behavior(true)
	for frame in 180:await physics_frame
	check(blocked.position.z<.45 and blocked.animation_player.speed_scale<.02,"collision-stopped body holds its gait instead of walking against the wall")
	var blocked_time:float=blocked.animation_player.current_animation_position
	for frame in 30:await physics_frame
	check(absf(blocked.animation_player.current_animation_position-blocked_time)<.002,"blocked feet retain their pose while requested movement stays nonzero")
	wall.position.x=-30
	var released_z:float=blocked.position.z
	for frame in 60:await physics_frame
	check(blocked.position.z-released_z>.30 and absf(blocked.animation_player.speed_scale-1.0)<.05,"clearing the collision resumes matched body and gait travel")
	blocked.set_physics_process(false);blocked.set_behavior(false)
	DirAccess.make_dir_recursive_absolute("res://reports/zombie_drag_walk")
	FileAccess.open("res://reports/zombie_drag_walk/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"left_sole_min":left_min,"left_sole_max":left_max,"right_sole_min":right_min,"right_sole_max":right_max,"stance_drift_m":absf(stance_end-stance_start),"left_boot_drift_m":left_drift,"right_boot_drift_m":right_drift,"pelvis_range":pelvis_max-pelvis_min,"right_arm_swing_m":arm_max-arm_min,"seam_error":seam_error,"samples":rows,"native_peak_work":peak_work,"scope":"Flat-floor evaluated skin and live shared-navigation controller lifecycle; no terrain foot IK or complete-world traversal claim."},"  "))
	encounters.clear();await process_frame;stage.free();await process_frame
	print("ZOMBIE_DRAG_WALK checks=",checks," failures=",failures);quit(1 if failures else 0)
