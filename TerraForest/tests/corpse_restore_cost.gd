# SPDX-License-Identifier: 0BSD
extends SceneTree
const Zombie=preload("res://addons/characters/runtime/zombie.gd")
class CloudMesh extends Mesh:
	var points:PackedVector3Array
	func _get_surface_count()->int:return 1
	func _surface_get_arrays(_index:int)->Array:
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=points;return arrays
	func _get_aabb()->AABB:return AABB()
class ObservedZombie extends Zombie:
	var debris_builds:=0
	var sever_us:=0
	func sever_limb(part:String,impulse:Vector3=Vector3.ZERO,emit_debris:bool=true)->void:
		var began:=Time.get_ticks_usec()
		super.sever_limb(part,impulse,emit_debris)
		sever_us+=Time.get_ticks_usec()-began
	func _spawn_detached(part:String,chain:Array[String],impulse:Vector3)->void:
		debris_builds+=1
		super._spawn_detached(part,chain,impulse)
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	if not value:failures+=1;push_error(label)
func run()->void:
	for parts:Array in [["head"],["upper_arm_l","forearm_l","hand_l"],["hand_r","foot_l"]]:
		var mask:=0;var index:=0
		for part:String in Zombie.PARTS:
			if part in parts:mask|=1<<index
			index+=1
		var actor:=ObservedZombie.new(true,mask);actor.defer_configuration=true;actor.set_simulation_available(false);actor.hide();root.add_child(actor)
		check(not actor.initialized,"staged admission does not initialize in tree attachment")
		var slices:=0
		while not actor.initialized and not actor.configuration_failed:
			actor.prepare_configuration_step(750);slices+=1;await process_frame
		check(slices>1 and not actor.visible and actor.process_mode==Node.PROCESS_MODE_DISABLED,"configuration yields while actor stays hidden and unavailable")
		check(actor.initialized,"actor initialized")
		if OS.get_cmdline_user_args().has("--clean-hull-probe"):
			var points:PackedVector3Array=actor.anatomy.sample_vertices("head",Transform3D.IDENTITY)
			var cloud:Dictionary=actor.anatomy.prepare_collision_cloud(points)
			var mesh:=CloudMesh.new();mesh.points=cloud.points
			var clean_begin:=Time.get_ticks_usec();var clean:=mesh.create_convex_shape(true,false)
			var clean_us:=Time.get_ticks_usec()-clean_begin
			var installs:Array=[]
			for candidate:bool in [false,true,false,true]:
				var shape:=ConvexPolygonShape3D.new();shape.points=clean.points if candidate else cloud.points;shape.margin=.003
				var body:=StaticBody3D.new();root.add_child(body);var collision:=CollisionShape3D.new();collision.shape=shape
				var install_begin:=Time.get_ticks_usec();body.add_child(collision);installs.append({"clean":candidate,"us":Time.get_ticks_usec()-install_begin});body.free()
			print("CLEAN_HULL_PROBE ",JSON.stringify({"original":cloud.points.size(),"clean":clean.points.size(),"clean_us":clean_us,"installs":installs}))
		var began:=Time.get_ticks_usec()
		actor.begin_corpse_restore(mask);await process_frame
		while not actor.prepare_corpse_step(1500):await process_frame
		actor.set_simulation_available(true);actor.show()
		var elapsed:=Time.get_ticks_usec()-began
		for part:String in Zombie.PARTS:
			check(bool(actor.missing.get(part,false))==(part in parts),"saved missing limb restored: "+part)
			check(actor.part_meshes[part].visible==(part not in parts),"saved mesh visibility restored: "+part)
			check(actor.physical_bones.has(actor.PARTS[part].bone)==(part not in parts),"saved physical anatomy restored: "+part)
		check(actor.detached_parts.is_empty() and actor.visible and not actor.alive,"restored corpse has no detached debris and is visible/dead")
		check(actor.debris_builds==0,"restoration must not build discarded debris")
		print("CORPSE_RESTORE_COST parts=",parts," debris_builds=",actor.debris_builds," sever_us=",actor.sever_us," elapsed_with_frame_wait_us=",elapsed)
		print("COLLISION_PROFILE ",JSON.stringify(actor.ragdoll_profile))
		print("INITIALIZATION_PROFILE ",JSON.stringify(actor.initialization_us))
		actor.queue_free();await process_frame;await process_frame
	print("CORPSE_RESTORE_COST failures=",failures)
	quit(0 if failures==0 else 1)
