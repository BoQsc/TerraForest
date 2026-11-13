# SPDX-License-Identifier: 0BSD
extends SceneTree
## Same authored geometry and deterministic rays before/after the native change.
const Zombie=preload("res://addons/characters/runtime/zombie.gd")
class ObservedZombie extends Zombie:
	var costs:Dictionary={}
	func _begin_ragdoll(impulse:Vector3)->void:
		var began:=Time.get_ticks_usec();super._begin_ragdoll(impulse);costs.ragdoll_us=Time.get_ticks_usec()-began
	func _refresh_pose_collision_shapes()->void:
		var began:=Time.get_ticks_usec();super._refresh_pose_collision_shapes();costs.collision_us=Time.get_ticks_usec()-began
	func _pose_shape_spec(part:String,pelvis:bool=false)->Dictionary:
		var began:=Time.get_ticks_usec();var result:=super._pose_shape_spec(part,pelvis)
		costs["shape_"+part+("_pelvis" if pelvis else "")]=Time.get_ticks_usec()-began;return result
	func _install_hand_compound(body:PhysicsBody3D,part:String,to_local:Transform3D)->void:
		var began:=Time.get_ticks_usec();super._install_hand_compound(body,part,to_local);costs["compound_"+part]=Time.get_ticks_usec()-began
var output:=""
var reference:=""
var failures:=0
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--pick-output="):output=arg.trim_prefix("--pick-output=")
		if arg.begins_with("--pick-reference="):reference=arg.trim_prefix("--pick-reference=")
	run.call_deferred()
func run()->void:
	if output.is_empty():quit(2);return
	var actor:=ObservedZombie.new();actor.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(actor)
	if not actor.initialized:quit(2);return
	var results:Array=[]
	var timings:Array[float]=[]
	var bake_timings:Dictionary={}
	var contact_timings:Dictionary={}
	# Translation and rotation exercise world-space bounds. Rays hit, graze and
	# miss each limb in idle, walking, attack and morphed geometry.
	actor.transform=Transform3D(Basis(Vector3.UP,.7),Vector3(1008,43,590))
	var camera:=Camera3D.new();root.add_child(camera);camera.position=actor.position+Vector3(0,1.2,3);camera.look_at(actor.position+Vector3.UP);camera.make_current()
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	await process_frame
	for pose:String in ["Zombie_Idle","Zombie_Walk_Drag_Right","Zombie_Attack_Left","morph"]:
		var clip:String=actor._animation_key("Zombie_Idle" if pose=="morph" else pose)
		if not actor.animation_player.has_animation(clip):failures+=1;continue
		actor.animation_player.play(clip);actor.animation_player.seek(.45,true);actor.animation_player.advance(0)
		if pose=="morph":
			for part:String in actor.part_meshes:
				var mesh:MeshInstance3D=actor.part_meshes[part]
				for index in mesh.get_blend_shape_count():mesh.set_blend_shape_value(index,.35)
		for part:String in Zombie.PARTS:
			var points:PackedVector3Array=actor.anatomy.sample_vertices(part,Transform3D.IDENTITY)
			if points.is_empty():failures+=1;continue
			var bounds:=AABB(points[0],Vector3.ZERO)
			for point:Vector3 in points:bounds=bounds.expand(point)
			var center:=bounds.get_center()
			for offset:Vector3 in [Vector3.ZERO,Vector3(.03,.025,0),Vector3(1.5,0,0)]:
				var from:Vector3=center+offset+Vector3(0,0,2)
				var to:Vector3=center+offset-Vector3(0,0,2)
				var began:=Time.get_ticks_usec()
				var hit:Dictionary=actor.anatomy.pick(from,to)
				timings.append(float(Time.get_ticks_usec()-began))
				results.append({"pose":pose,"part":part,"hit":hit.get("part",""),"fraction":hit.get("fraction",-1.0),"position":hit.get("position",Vector3.ZERO),"normal":hit.get("normal",Vector3.ZERO)})
	for part:String in ["hand_l","head","forearm_l","upper_arm_l"]:
		var began:=Time.get_ticks_usec()
		var baked:ArrayMesh=actor._bake_cpu(actor.part_meshes[part],actor.global_transform.affine_inverse())
		bake_timings[part]=Time.get_ticks_usec()-began
		if baked.get_surface_count()==0:failures+=1
		began=Time.get_ticks_usec()
		actor.anatomy.closest_contact(part,actor.global_position+Vector3(0,1.5,.7),true,[],AABB(Vector3(-.027,1.597,.098),Vector3(.054,.027,.024)))
		contact_timings[part]=Time.get_ticks_usec()-began
	var detach_started:=Time.get_ticks_usec()
	actor.sever_limb("forearm_l")
	var detach_us:=Time.get_ticks_usec()-detach_started
	actor.die()
	await process_frame;await process_frame
	var comparisons:=0
	if not reference.is_empty():
		var expected:Variant=JSON.parse_string(FileAccess.get_file_as_string(reference))
		if not expected is Dictionary or expected.results.size()!=results.size():failures+=1
		else:
			for index in results.size():
				var a:Dictionary=results[index];var b:Dictionary=expected.results[index]
				if a.pose!=b.pose or a.part!=b.part or a.hit!=b.hit or absf(a.fraction-float(b.fraction))>.00001 or str(a.position)!=b.position or str(a.normal)!=b.normal:failures+=1
				comparisons+=1
	timings.sort()
	var report:Dictionary={"results":results,"queries":timings.size(),"median_us":timings[timings.size()/2],"p95_us":timings[int(timings.size()*.95)],"max_us":timings[-1],"comparisons":comparisons,"failures":failures,"geometry":actor.anatomy.geometry_stats(),"bake_us":bake_timings,"contact_us":contact_timings,"detach_us":detach_us,"death_costs":actor.costs}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report))
	actor.free();camera.free();await process_frame
	print("ZOMBIE_PICK_PERFORMANCE queries=",timings.size()," median_us=",report.median_us," p95_us=",report.p95_us," detach_us=",detach_us," bake_us=",bake_timings," contact_us=",contact_timings," death_costs=",report.death_costs," comparisons=",comparisons," failures=",failures)
	quit(0 if failures==0 else 1)
