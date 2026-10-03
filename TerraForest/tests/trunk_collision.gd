# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var batch=ClassDB.instantiate("NativeStaticBatch")
	check(batch.configure_asset("tests/trunk",BoxMesh.new()) and batch.configure_collision_only() and batch.configure_collision(AABB(Vector3(-.35,0,-.35),Vector3(.7,8,.7)),32,8,2),"bounded collision-only batch configured")
	root.add_child(batch)
	var ids:=PackedInt64Array();var transforms: Array[Transform3D]=[]
	for i in 40:
		ids.append(i+1);transforms.append(Transform3D(Basis.from_euler(Vector3(0,.3,0)),Vector3(i*2,0,0)))
	check(batch.upsert_transforms(ids,transforms),"native transform upload accepts tree batch")
	batch.set_collision_focus(Vector3.ZERO)
	for tick in 8: await physics_frame
	var stats: Dictionary=batch.collision_stats()
	print("TRUNK_STATS ",stats," render=",batch.render_stats())
	check(stats.resident_bodies==8 and stats.budget_deferred>0,"nearby collider budget is enforced")
	check(batch.render_stats().resident_batches==0 and batch.render_stats().resident_transform_bytes==0,"physics-only roots allocate no render batches")
	var hit:=root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,1,-2),Vector3(0,1,2),2))
	check(not hit.is_empty(),"near trunk participates in physics ray collision")
	check(batch.remove_instances(PackedInt64Array([1])),"root removal accepted")
	await physics_frame;await physics_frame
	hit=root.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,1,-2),Vector3(0,1,2),2))
	check(hit.is_empty(),"removed root has no ghost collider")
	batch.free()
	var vegetation=load("res://addons/vegetation/vegetation_world.gd").new();root.add_child(vegetation)
	# Render setup is unnecessary for owner/removal bookkeeping in this fixture.
	vegetation.ready_to_render=true
	check(vegetation.enable_trunk_collision(),"vegetation enables native trunk collision")
	var tree_transforms: Array[Transform3D]=[Transform3D.IDENTITY,Transform3D(Basis.IDENTITY,Vector3(10,0,0))]
	check(vegetation.upsert_chunk("test",PackedInt64Array([1,2]),tree_transforms),"vegetation publishes render and collision roots")
	check(vegetation.remove_roots_in_bounds(AABB(Vector3(-1,-1,-1),Vector3(2,2,2)))==1,"local removal targets one tree")
	vegetation.remove_chunk("test")
	check(vegetation._collision_sync_ok and vegetation.trunk_collision.get_ids().is_empty(),"chunk retirement tolerates previously removed roots")
	vegetation.free();quit(0 if failures==0 else 1)
