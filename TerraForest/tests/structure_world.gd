extends SceneTree
const Scene = preload("res://demo/world.tscn")
const Presentation = preload("res://addons/presentation/fullscreen_policy.gd")
var game: Node3D
var checks: Array[Dictionary] = []
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks.append({"name":label,"pass":value})
	if not value:
		failures += 1
	print(("PASS " if value else "FAIL ")+label)

func until(predicate: Callable, seconds := 60) -> bool:
	var deadline := Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await process_frame
	return predicate.call()

func run() -> void:
	game=Scene.instantiate()
	game.temporary_world=true
	root.add_child(game)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	check(await until(func(): return not game.loading_active and game.terrain.world_ready),"main terrain scene finishes its loading gate")
	if failures:
		finish()
		return
	check(await until(func(): return game.vegetation.renderer.roots.size()>0),"natural vegetation is resident before construction")
	if failures:
		finish()
		return
	var tree_id: int = game.vegetation.renderer.roots.keys()[0]
	var tree_transform: Transform3D = game.vegetation.renderer.roots[tree_id]["t"]
	var tree_owner: String = game.vegetation.renderer.roots[tree_id]["owner"]
	var tree_cell := Vector3i(tree_transform.origin.floor())+Vector3i(0,5,0)
	var empty_blocks: PackedByteArray = game.structures.blocks.capture_snapshot()
	game.structures.blocks.set_cells(PackedInt32Array([tree_cell.x,tree_cell.y,tree_cell.z,1]))
	var occupied_blocks: PackedByteArray = game.structures.blocks.capture_snapshot()
	check(await until(func(): return not game.vegetation.renderer.roots.has(tree_id)),"placing a block removes an intersecting tree canopy")
	game.structures.blocks.restore_snapshot(empty_blocks)
	check(await until(func(): return game.vegetation.renderer.roots.has(tree_id)),"removing construction restores the deterministic tree candidate")
	check(game.vegetation.renderer.roots.get(tree_id,{}).get("t",Transform3D())==tree_transform,"restored tree keeps its original placement")
	game.structures.blocks.restore_snapshot(occupied_blocks)
	check(await until(func(): return not game.vegetation.renderer.roots.has(tree_id)),"snapshot restore also reapplies occupancy exclusion")
	game.ecosystem.reset()
	check(await until(func(): return game.vegetation.renderer.owners.has(tree_owner)),"forest owner is regenerated after residency reset")
	check(not game.vegetation.renderer.roots.has(tree_id),"regenerated forest does not grow through saved blocks")
	game.structures.blocks.restore_snapshot(empty_blocks)
	check(await until(func(): return game.vegetation.renderer.roots.has(tree_id)),"regenerated blocked candidate remains available after demolition")
	var origin: Vector3 = game.player.position+Vector3(0,0,-12)
	var hit := game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(origin+Vector3.UP*64,origin-Vector3.UP*64,1))
	check(not hit.is_empty(),"construction site has real terrain collision")
	if hit.is_empty():
		finish()
		return
	var site := Vector3i(hit.position.floor())+Vector3i(0,2,0)
	var records := PackedInt32Array()
	for z in range(-4,5):
		for x in range(-4,5):
			for y in range(-2,4):
				var floor_cell := y<=0
				var wall := y>0 and (x==-4 or x==4 or z==4) and not (y==2 and x>-3 and x<3)
				if floor_cell or wall:
					var p := site+Vector3i(x,y,z)
					records.append_array(PackedInt32Array([p.x,p.y,p.z,1+(64 if floor_cell else 0)]))
	var isolated := site+Vector3i(0,6,0)
	records.append_array(PackedInt32Array([isolated.x,isolated.y,isolated.z,1]))
	check(game.structures.blocks.set_cells(records),"native foundation/walls and editing target created in terrain world")
	game.structures.blocks.set_focus(Vector3(site))
	check(await until(func(): return game.structures.blocks.is_idle(),20),"building chunk meshes publish in the main scene")
	await physics_frame
	await physics_frame
	var b := InputEventKey.new()
	b.physical_keycode=KEY_B
	b.pressed=true
	game.held_previous=true
	game.stroke_valid=true
	game.last_capture_signature={"test":true}
	game._unhandled_input(b)
	check(game.structure_mode,"B selects independent block construction")
	check(not game.held_previous and not game.stroke_valid and game.last_capture_signature.is_empty(),"tool mode switch cannot carry a terrain stroke into later editing")
	game.fly=true
	game.app_focused=true
	game.player.position=Vector3(isolated)+Vector3(0.5,6,0.5)
	game.camera.look_at(Vector3(isolated)+Vector3(0.5,0.5,0.5),Vector3.FORWARD)
	var revision: int = game.terrain.density_revision
	game._edit_structure(false)
	check(game.structures.blocks.get_cell(isolated+Vector3i.UP)==1,"actual construction picking places the adjacent block")
	check(await until(func(): return game.structures.blocks.is_idle(),20),"placed block mesh publishes")
	await physics_frame
	await physics_frame
	game._edit_structure(true)
	check(game.structures.blocks.get_cell(isolated+Vector3i.UP)==0,"actual construction picking removes the selected block")
	check(game.terrain.density_revision==revision,"block authoring does not mutate terrain density")
	game.structures.blocks.set_cells(PackedInt32Array([isolated.x,isolated.y,isolated.z,0]))
	check(await until(func(): return game.structures.blocks.is_idle(),20),"temporary editing target removed")
	await physics_frame
	await physics_frame
	game.player.position=Vector3(site)+Vector3(0.5,3,0.5)
	game.player.velocity=Vector3.ZERO
	game.fly=false
	for i in range(120):
		await physics_frame
	check(game.player.is_on_floor() and game.player.position.y>site.y+0.9,"existing player stands on independent building collision")
	var models: Node3D = game.structures.model("architecture/metal_beam/v1")
	check(models.upsert_instances(PackedInt64Array([101]),PackedFloat32Array([6,0,0,site.x,0,0.15,0,site.y+4.0,0,0,0.15,site.z-3.0])),"static model placement shares the main world structures owner")
	var bundle: Dictionary = game.structures.snapshot_validator().decode(game.structures.capture_snapshot())
	check(bundle.ok and bundle.models.size()==1,"main scene captures blocks and static models as one validated component")
	game.fly=true
	game.player.position=Vector3(site)+Vector3(10,8,15)
	game.player.velocity=Vector3.ZERO
	game.camera.look_at(Vector3(site)+Vector3(0,1,0))
	check(await until(func(): return game.ecosystem._reconcile.is_empty()),"building exclusion reconciliation drains")
	var live_transforms: Array[Transform3D] = []
	for row in game.vegetation.renderer.roots.values():
		live_transforms.append(row["t"])
	var overlaps: PackedByteArray = game.structures.blocks.overlap_mask(live_transforms,game.vegetation.placement_bounds())
	check(overlaps.size()==live_transforms.size() and overlaps.count(1)==0,"no resident tree canopy overlaps any occupied building cell")
	check(game.ecosystem._samples.size()<=game.ecosystem.max_resident_cells,"cached candidates stay within the residency budget")
	var rejected_key := Vector2i(31,31)
	game.ecosystem._samples[rejected_key] = {"published":false}
	game.ecosystem._reconcile[rejected_key] = true
	game.ecosystem._refresh(game.ecosystem._cell(game.camera.global_position))
	check(not game.ecosystem._samples.has(rejected_key) and not game.ecosystem._reconcile.has(rejected_key),"eviction reclaims samples even when publication had failed")
	await create_timer(1.0).timeout
	if DisplayServer.get_name()!="headless":
		check(Presentation.measurement(root).fair_graphical_sample,"integrated construction view is 1920x1080 fullscreen at full scale")
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://reports")
		root.get_texture().get_image().save_png("res://reports/structure_world.png")
	finish()

func finish() -> void:
	game.terrain.shutdown()
	game.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/structure_world.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	file.close()
	quit(1 if failures else 0)
