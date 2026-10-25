# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var scene:=Node3D.new();root.add_child(scene)
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld");scene.add_child(blocks)
	var floor:=StaticBody3D.new();floor.collision_layer=1;floor.collision_mask=0
	var shape:=BoxShape3D.new();shape.size=Vector3(16,.5,16)
	var collision:=CollisionShape3D.new();collision.shape=shape;floor.add_child(collision);scene.add_child(floor)
	var bounds:=AABB(Vector3.ZERO,Vector3.ONE)
	for height:float in [.12,.82]:
		floor.position=Vector3(.5,height-.25,.5)
		await physics_frame;await physics_frame
		var fit:Dictionary=blocks.placement_support(bounds,Vector3(.5,height,.5),true,true,[])
		check(fit.ok and fit.samples==9 and fit.hits==9,"fixed native footprint resolves flat ground at %.2f m"%height)
		check(is_equal_approx(float(fit.bottom),0.0 if height<.2 else 1.0),"shallow overlap stays on-grid; deeply buried cube moves up")
		check(height-float(fit.bottom)<=.201,"block burial is limited to 20 cm")
	var thin:Dictionary=blocks.placement_support(AABB(Vector3.ZERO,Vector3(1,.5,1)),Vector3(.5,.82,.5),true,true,[])
	check(thin.ok and is_equal_approx(float(thin.overlap_limit),.125),"thin blocks use a proportional overlap limit")
	for height:float in [.12,.35,.55,.59,.65,.82]:
		floor.position=Vector3(.5,height-.25,.5)
		await physics_frame;await physics_frame
		var normal:Dictionary=blocks.placement_support(bounds,Vector3(.5,height,.5),true,true,[])
		var preferred:Dictionary=blocks.placement_support(bounds,Vector3(.5,height,.5),true,true,[],true)
		check(preferred.ok and preferred.hits==9 and is_equal_approx(preferred.bottom,0.0 if height<.6 else 1.0),"opt-in lower cell prefers moderate burial over a larger gap at %.2f"%height)
		check(preferred.maximum-preferred.bottom<=.60001 and preferred.gap<=normal.gap+.00001,"burial trial retains visible cube height and cannot increase air gap")
		var plate_bounds:=AABB(Vector3.ZERO,Vector3(1,.25,1))
		check(blocks.placement_support(plate_bounds,Vector3(.5,height,.5),true,true,[],true)==blocks.placement_support(plate_bounds,Vector3(.5,height,.5),true,true,[]),"thin plates retain their original overlap limit")
		check(blocks.placement_support(bounds,Vector3(.5,height,.5),false,true,[],true)==blocks.placement_support(bounds,Vector3(.5,height,.5),false,true,[]),"non-grid objects retain original targeting")
	floor.position=Vector3(.5,.82-.25,.5)
	floor.rotation.z=deg_to_rad(10)
	await physics_frame;await physics_frame
	var object_bounds:=AABB(Vector3(-.5,.82,-.5),Vector3(2,1,2))
	var object_fit:Dictionary=blocks.placement_support(object_bounds,Vector3(.5,.82,.5),false,false,[])
	check(object_fit.ok and float(object_fit.maximum)-float(object_fit.bottom)<=.031 and float(object_fit.gap)<.6,"object footprint settles above uphill ground with only slight base overlap")
	floor.rotation.z=deg_to_rad(35)
	await physics_frame;await physics_frame
	var steep:Dictionary=blocks.placement_support(object_bounds,Vector3(.5,.82,.5),false,false,[])
	check(not steep.ok and str(steep.reason).contains("uneven"),"extreme unevenness is explained instead of burying or greatly floating an object")
	check(not blocks.placement_support(AABB(Vector3.ZERO,Vector3(100,1,100)),Vector3.ZERO,false,false,[]).ok,"oversized footprint is rejected before unbounded work")
	check(not blocks.placement_support(bounds,Vector3(NAN,0,0),true,true,[]).ok,"non-finite support request is rejected")
	check(not blocks.placement_support(bounds,Vector3(1e20,0,0),true,true,[]).ok,"out-of-range support request is rejected before physics queries")
	floor.collision_layer=0
	await physics_frame;await physics_frame
	check(not blocks.placement_support(bounds,Vector3(.5,.82,.5),true,true,[]).ok,"missing ground is unavailable rather than guessed")
	blocks.set_cells(PackedInt32Array([0,0,0,1]))
	var stacked:Dictionary=blocks.placement_support(AABB(Vector3(0,1,0),Vector3.ONE),Vector3(.5,1,.5),false,false,[])
	check(stacked.ok and stacked.hits==9 and absf(float(stacked.maximum)-1)<.001,"authored block support resolves before derived collision is baked")
	scene.free();await process_frame
	print("PLACEMENT_SUPPORT failures=",failures);quit(1 if failures else 0)
