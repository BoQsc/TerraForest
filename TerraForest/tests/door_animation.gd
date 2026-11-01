# SPDX-License-Identifier: 0BSD
extends SceneTree
const MOTION=preload("res://addons/structures/door_animation/bg5_motion.scn")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func settle()->void:
	for frame in 3:await physics_frame;await process_frame
func state()->RefCounted:
	var hinges:RefCounted=ClassDB.instantiate("NativeHingedDoors")
	check(hinges.configure_animation(MOTION.get_meta("open_curve"),MOTION.get_meta("close_curve")),"authored GLB hinge curves configure")
	return hinges
func run()->void:
	var world=preload("res://addons/structures/structures_world.gd").new();root.add_child(world);world.prepare()
	var entry:Dictionary=preload("res://addons/structures/door_catalog.gd").register(world)
	var batch:Node3D=entry.collection;var hinges:=state()
	var closed:=PackedFloat32Array([1,0,0,0,0,1,0,0,0,0,1,0])
	batch.upsert_instances(PackedInt64Array([7]),closed);batch.set_collision_focus(Vector3.ZERO);batch.set_render_focus(Vector3.ZERO)
	for frame in 15:await physics_frame;await process_frame
	var body:RID=batch.collision_body_for(7);var builds:int=batch.collision_stats().body_builds
	check(body.is_valid(),"ordinary native door collision is resident")
	var rig:Node3D=MOTION.instantiate();root.add_child(rig);var player:AnimationPlayer=rig.get_node("AnimationPlayer")
	check(player.has_animation("Open") and player.has_animation("Close"),"runtime retains authored Open and Close")
	check(player.get_animation("Open").get_track_count()==3 and player.get_animation("Close").get_track_count()==3,"both authored handle channels and latch are retained in both clips")
	player.assigned_animation="Open";player.seek(0,true)
	var front:Transform3D=rig.get_node("HandleFrontPivot").transform
	var back:Transform3D=rig.get_node("HandleBackPivot").transform
	var latch:Transform3D=rig.get_node("LatchPivot").transform
	player.seek(.1,true)
	check(not rig.get_node("HandleFrontPivot").transform.is_equal_approx(front) and not rig.get_node("HandleBackPivot").transform.is_equal_approx(back),"authored early handle press moves both levers")
	check(not rig.get_node("LatchPivot").transform.is_equal_approx(latch),"authored latch retracts")
	check(hinges.animate_toggle(batch,7,AABB()).ok and hinges.is_open(7) and hinges.is_moving(7),"ordinary animation starts without snapping")
	check(batch.get_instance(7)==closed,"leaf initially retains authored closed hold")
	hinges.advance(batch,.1)
	check(batch.get_instance(7)==closed,"authored handle-first timing precedes leaf swing")
	check(not hinges.animate_toggle(batch,7,AABB()).ok,"repeated use cannot restart an active clip")
	for frame in 4:hinges.advance(batch,.1);await settle()
	var middle:PackedFloat32Array=batch.get_instance(7)
	check(middle!=closed and hinges.motion_state(7).fraction>0 and hinges.motion_state(7).fraction<1,"leaf reaches an intermediate authored pose")
	check(batch.collision_body_for(7)==body and batch.collision_stats().body_builds==builds,"motion retains its collision body without proxy rebuilds")
	var pose:=Transform3D(Basis(Vector3(middle[0],middle[4],middle[8]),Vector3(middle[1],middle[5],middle[9]),Vector3(middle[2],middle[6],middle[10])),Vector3(middle[3],middle[7],middle[11]))
	var centre:Vector3=pose*Vector3(.5,1,0)
	var ray=root.world_3d.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(centre+pose.basis.z,centre-pose.basis.z,2))
	check(ray.get("rid",RID())==body,"collision follows the actual intermediate leaf")
	var models:PackedByteArray=batch.capture_snapshot();var saved:PackedByteArray=hinges.capture_storage_snapshot()
	check(saved.decode_u32(0)==0x33524454 and hinges.validate_snapshot(saved),"mid-animation packet validates its authored curve identity")
	check(batch.set_instance_visual_hidden(7,true) and batch.is_instance_visual_hidden(7) and batch.capture_snapshot()==models and batch.collision_body_for(7)==body,"active rig can replace only the batched visual without touching storage or collision")
	batch.set_instance_visual_hidden(7,false)
	var blocker:=StaticBody3D.new();blocker.collision_layer=1<<16;blocker.collision_mask=0
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.3,1,.3);shape.shape=box;blocker.add_child(shape);root.add_child(blocker);blocker.position=Vector3(.5,1,-.5);await settle()
	check(hinges.advance(batch,.1)==0 and hinges.is_blocked(7) and batch.capture_snapshot()==models,"an actor entering the swing pauses motion without penetration")
	blocker.free();await settle()
	var restored:=state()
	check(restored.restore_storage_snapshot(saved) and batch.restore_snapshot(models),"mid-swing hinge and model state restore together")
	check(restored.motion_state(7).time==hinges.motion_state(7).time,"restore retains authored playback time")
	for frame in 14:restored.advance(batch,.1)
	check(not restored.is_moving(7) and restored.is_open(7),"restored clip completes at the open endpoint")
	check(restored.capture_storage_snapshot().decode_u32(0)==0x31524454,"finished motion retains the legacy settled-state packet")
	check(restored.animate_toggle(batch,7,AABB()).ok,"authored Close starts")
	for frame in 14:restored.advance(batch,.1)
	check(not restored.is_open(7) and not restored.is_moving(7) and batch.get_instance(7)==closed,"authored Close returns to byte-exact original placement")
	check(restored.animate_toggle(batch,7,AABB()).ok,"open before editor interruption")
	restored.advance(batch,.1);var moved:PackedFloat32Array=batch.get_instance(7);moved[3]+=5;batch.upsert_instances(PackedInt64Array([7]),moved)
	restored.advance(batch,.1)
	check(not restored.is_moving(7) and batch.get_instance(7)==moved,"editor relocation cancels stale motion without teleporting")
	var bad:=saved.duplicate();bad[56]^=1
	check(not restored.restore_storage_snapshot(bad),"incompatible authored curve packet fails safely")
	rig.free();world.free();await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports")
	FileAccess.open("res://reports/door_animation.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}))
	print("DOOR_ANIMATION checks=",checks," failures=",failures);quit(1 if failures else 0)
