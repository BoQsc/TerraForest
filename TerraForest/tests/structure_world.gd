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
	check(game.structures.blocks.undo() and await until(func(): return game.vegetation.renderer.roots.has(tree_id)),"undo restores vegetation excluded by construction")
	check(game.structures.blocks.redo() and await until(func(): return not game.vegetation.renderer.roots.has(tree_id)),"redo reapplies construction vegetation exclusion")
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
	var exclusion_models: Node3D = game.structures.model("architecture/metal_beam/v1")
	var empty_models: PackedByteArray = exclusion_models.capture_snapshot()
	var tree_point := tree_transform.origin+Vector3(0,5,0)
	var model_record := PackedFloat32Array([1,0,0,tree_point.x,0,1,0,tree_point.y,0,0,1,tree_point.z])
	exclusion_models.upsert_instances(PackedInt64Array([99]),model_record)
	var occupied_models: PackedByteArray = exclusion_models.capture_snapshot()
	check(await until(func(): return not game.vegetation.renderer.roots.has(tree_id)),"placed static model excludes an intersecting tree canopy")
	exclusion_models.position=Vector3(10000,0,0)
	check(await until(func(): return game.vegetation.renderer.roots.has(tree_id)),"collection transform change restores eligible vegetation")
	exclusion_models.position=Vector3.ZERO
	check(await until(func(): return not game.vegetation.renderer.roots.has(tree_id)),"returning model collection reapplies vegetation exclusion")
	exclusion_models.restore_snapshot(empty_models)
	check(await until(func(): return game.vegetation.renderer.roots.has(tree_id)),"removing models restores cached tree candidates")
	check(game.vegetation.renderer.roots.get(tree_id,{}).get("t",Transform3D())==tree_transform,"model removal preserves deterministic tree placement")
	exclusion_models.restore_snapshot(occupied_models)
	check(await until(func(): return not game.vegetation.renderer.roots.has(tree_id)),"restored model records reapply vegetation exclusion")
	game.ecosystem.reset()
	check(await until(func(): return game.vegetation.renderer.owners.has(tree_owner)),"model exclusion survives forest residency reset")
	check(not game.vegetation.renderer.roots.has(tree_id),"regenerated trees do not grow through saved static models")
	exclusion_models.restore_snapshot(empty_models)
	check(await until(func(): return game.vegetation.renderer.roots.has(tree_id)),"demolition restores trees after model-driven forest regeneration")
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
	var before_placement: PackedByteArray = game.structures.capture_snapshot()
	game._edit_structure(false)
	check(game.structures.blocks.get_cell(isolated+Vector3i.UP)==1,"actual construction picking places the adjacent block")
	var after_placement: PackedByteArray = game.structures.capture_snapshot()
	var undo_key := InputEventKey.new()
	undo_key.physical_keycode=KEY_Z
	undo_key.ctrl_pressed=true
	undo_key.pressed=true
	game._unhandled_input(undo_key)
	check(game.structures.capture_snapshot()==before_placement,"Ctrl+Z reverses the edit and invalidates cached world persistence")
	var redo_key := InputEventKey.new()
	redo_key.physical_keycode=KEY_Y
	redo_key.ctrl_pressed=true
	redo_key.pressed=true
	game._unhandled_input(redo_key)
	check(game.structures.capture_snapshot()==after_placement,"Ctrl+Y restores the edit and its persistent representation")
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
	check(models.upsert_instances(PackedInt64Array([102]),PackedFloat32Array([6,0,0,site.x,0,0.5,0,site.y+4.0,0,0,6,site.z-10.0])),"place a separate static-model platform")
	check(await until(func(): return models.collision_stats().resident_bodies==2),"main scene admits nearby model collision proxies")
	var model_hit := game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(site)+Vector3(0,8,-10),Vector3(site)+Vector3(0,2,-10),2))
	check(not model_hit.is_empty() and model_hit.collider==models and models.placement_for_body(model_hit.rid)==102,"main-world model picking returns stable placement identity")
	game.player.position=Vector3(site)+Vector3(0,7,-10)
	game.player.velocity=Vector3.ZERO
	for i in range(120):
		await physics_frame
	check(game.player.is_on_floor() and game.player.position.y>site.y+4.0,"existing player stands on independently placed static model")
	var bundle: Dictionary = game.structures.snapshot_validator().decode(game.structures.capture_snapshot())
	check(bundle.ok and bundle.models.size()==2,"main scene captures blocks and static models as one validated component")
	var doors: Node3D = game.structures.model("architecture/doorway/v1")
	check(doors.upsert_instances(PackedInt64Array([201]),PackedFloat32Array([1,0,0,site.x,0,1,0,site.y+4.25,0,0,1,site.z-10.0])),"place reusable doorway model on the static platform")
	check(await until(func(): return doors.collision_stats().resident_shapes==3),"doorway publishes all three collision parts")
	var door_center := Vector3(site)+Vector3(0,5.25,-10)
	var door_query := PhysicsRayQueryParameters3D.create(door_center+Vector3(0,0,-2),door_center+Vector3(0,0,2),2)
	door_query.exclude=[game.player.get_rid()]
	var clear_door := game.get_world_3d().direct_space_state.intersect_ray(door_query)
	check(clear_door.is_empty(),"main-world doorway preserves its traversable opening")
	game.player.position=Vector3(site)+Vector3(0,4.3,-11.5)
	game.player.velocity=Vector3.ZERO
	var doorway_collision = game.player.move_and_collide(Vector3(0,0,3))
	check(doorway_collision==null and game.player.position.z>site.z-9,"actual world player passes through the static doorway")
	game.fly=true
	game.player.position=Vector3(site)+Vector3(10,8,15)
	game.player.velocity=Vector3.ZERO
	game.camera.look_at(Vector3(site)+Vector3(0,1,0))
	check(await until(func(): return game.ecosystem._reconcile.is_empty()),"building exclusion reconciliation drains")
	var live_transforms: Array[Transform3D] = []
	for row in game.vegetation.renderer.roots.values():
		live_transforms.append(row["t"])
	var overlaps: PackedByteArray = game.structures.overlap_mask(live_transforms,game.vegetation.placement_bounds())
	check(overlaps.size()==live_transforms.size() and overlaps.count(1)==0,"no resident tree canopy overlaps blocks or authored model proxies")
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
	await check_model_editor(Vector3(site))
	await check_prefab_editor(Vector3(site)+Vector3(22,0,0))
	await check_sphere_editor(Vector3(site))
	finish()

func check_sphere_editor(site: Vector3) -> void:
	game.fly=true
	game.model_tool.set_active(false)
	game.structure_mode=true
	game.structure_prefab_index=-1
	game.structure_rotation=0
	editor_key(KEY_6)
	check(game.structure_shape==6,"6 selects the native sphere block in the world editor")
	var revision: int = game.terrain.density_revision
	game.structures.blocks.set_collision_radius(0)
	check(await until(func(): return game.structures.blocks.stats().collision_chunks==0,10),"editor fixture removes all derived block collision")
	for material in range(4):
		var cell := Vector3i(site)+Vector3i(-3+material*2,1,0)
		game.player.position=Vector3(cell)+Vector3(0.5,6,0.5)
		game.player.velocity=Vector3.ZERO
		game.camera.look_at(Vector3(cell)+Vector3(0.5,-0.5,0.5),Vector3.FORWARD)
		game.structures.blocks.set_focus(Vector3(cell))
		check(await until(func():
			var picked: Dictionary = game._structure_target(false)
			return not picked.is_empty() and picked.target==cell
		,10),"sphere site has the expected construction support %d" % material)
		var model_hit: Dictionary = game.model_tool.ray()
		check(model_hit.get("collider")==game.structures.blocks and model_hit.has("cell"),"model placement ray sees authored support without block collision %d" % material)
		game.structure_material=material
		game._edit_structure(false)
		check(game.structures.blocks.get_cell(cell)==6+(material<<5),"actual block tool places sphere material %d" % material)
		var immediate: Dictionary = game._structure_target(true)
		check(not immediate.is_empty() and immediate.target==cell,"new sphere is immediately removable before baking %d" % material)
		check(await until(func(): return game.structures.blocks.is_idle(),20),"sphere chunk bake publishes material %d" % material)
	check(game.terrain.density_revision==revision,"sphere authoring leaves terrain density unchanged")
	game.structures.blocks.set_collision_radius(48)
	var saved: PackedByteArray = game.structures.capture_snapshot()
	check(game.structures.snapshot_validator().validate_snapshot(saved) and game.structures.restore_snapshot(saved),"compound world codec accepts and restores sphere blocks")
	check(await until(func(): return game.structures.blocks.is_idle() and game.ecosystem._reconcile.is_empty(),20),"restored spheres settle geometry and vegetation exclusion")
	game.player.position=site+Vector3(0,2,-6.5)
	game.camera.look_at(site+Vector3(0,1.5,0.5))
	await create_timer(1.0).timeout
	if DisplayServer.get_name()!="headless":
		check(Presentation.measurement(root).fair_graphical_sample,"sphere material evidence is 1920x1080 fullscreen at full scale")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/sphere_blocks.png")

func editor_key(code: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode=code
	event.pressed=true
	game._unhandled_input(event)

func check_model_editor(site: Vector3) -> void:
	game.fly=true
	game.player.position=site+Vector3(10,11,-3)
	game.player.velocity=Vector3.ZERO
	game.camera.look_at(site+Vector3(2,4.25,-8))
	editor_key(KEY_M)
	editor_key(KEY_3)
	check(game.model_tool.active and game.structure_mode and game.model_tool.panel.visible,"M opens the independent model placement catalog")
	check(game.model_tool.selected==2,"number keys select a model asset")
	var collection: Node3D = game.structures.model("architecture/doorway/v1")
	var before: PackedInt64Array = collection.get_ids()
	var before_save: PackedByteArray = game.structures.capture_snapshot()
	editor_key(KEY_R)
	game.model_tool.refresh()
	check(game.model_tool.quarter_turns==1 and game.model_tool.preview.visible and game.model_tool.preview_valid,"rotation updates a valid model ghost preview")
	var target: Dictionary = game.model_tool.target()
	check(not target.is_empty(),"model tool finds an actual support surface")
	if target.is_empty():
		editor_key(KEY_M)
		return
	var expected: PackedFloat32Array = game.model_tool.records(target.transform,collection)
	var click := InputEventMouseButton.new()
	click.button_index=MOUSE_BUTTON_RIGHT
	click.pressed=true
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	game._unhandled_input(click)
	var after: PackedInt64Array = collection.get_ids()
	check(after.size()==before.size()+1,"actual RMB tool input inserts one native placement")
	var id: int = after[-1]
	check(collection.get_instance(id)==expected,"placed transform matches the rotated preview")
	check(game.structures.capture_snapshot()!=before_save,"model tool edits invalidate compound world save cache")
	check(await until(func(): return collection.collision_stats().pending_bodies==0 and not collection.collision_stats().selection_pending),"placed model collision finishes admission")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/model_editor.png")
	var placed: Transform3D = target.transform
	var aim := placed*Vector3(-1.5,1.5,0)
	game.player.position=aim+Vector3(6,3,6)
	game.camera.look_at(aim)
	await check_model_transforms(collection,id,expected,aim)
	game.player.position=aim+Vector3(6,3,6)
	game.camera.look_at(aim)
	click.button_index=MOUSE_BUTTON_LEFT
	game._unhandled_input(click)
	check(collection.get_instance(id).is_empty() and collection.get_ids()==before,"LMB removes the picked model by stable placement ID")
	check(game.structures.capture_snapshot()==before_save,"removal restores the prior authored world content")
	var history_key := InputEventKey.new()
	history_key.physical_keycode=KEY_Z
	history_key.ctrl_pressed=true
	history_key.pressed=true
	game._unhandled_input(history_key)
	check(collection.get_instance(id)==expected,"model Ctrl+Z restores removed object with exact ID and transform")
	check(await until(func(): return collection.collision_stats().pending_bodies==0 and not collection.collision_stats().selection_pending),"model undo restores nearby collision admission")
	history_key.physical_keycode=KEY_Y
	game._unhandled_input(history_key)
	check(collection.get_instance(id).is_empty(),"model Ctrl+Y replays object removal")
	var outside: Vector3 = game.player.position
	game.player.position=aim-Vector3(0,0.8,0)
	history_key.physical_keycode=KEY_Z
	game._unhandled_input(history_key)
	check(collection.get_instance(id).is_empty() and game.model_tool.history.stats().undo_steps==2,"model undo cannot restore a doorway post through the player")
	game.player.position=outside
	game._unhandled_input(history_key)
	check(collection.get_instance(id)==expected,"blocked model undo remains retryable after moving clear")
	game._unhandled_input(history_key)
	check(collection.get_instance(id).is_empty() and game.structures.capture_snapshot()==before_save,"next model undo removes original placement and restores saved content")
	history_key.shift_pressed=true
	game._unhandled_input(history_key)
	check(collection.get_instance(id)==expected,"model Ctrl+Shift+Z restores original placement")
	history_key.physical_keycode=KEY_Y
	history_key.shift_pressed=false
	game._unhandled_input(history_key)
	check(game.structures.capture_snapshot()==before_save,"complete model redo chain returns to pre-test authored content")
	editor_key(KEY_M)
	check(not game.model_tool.active and game.structure_mode and not game.model_tool.preview.visible,"M returns to block editing and hides model preview")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE

func check_model_transforms(collection: Node3D, id: int, original: PackedFloat32Array, aim: Vector3) -> void:
	editor_key(KEY_E)
	check(game.model_tool.picked_id==id and game.model_tool.picked_collection==collection,"E selects the aimed model by native physics identity")
	check(game.model_tool.transform_controls.visible,"selection exposes transform buttons")
	game.model_tool.update(0.0,false)
	check(not game.model_tool.transform_selected(Vector3.RIGHT,0.0,1.0) and collection.get_instance(id)==original,"transform callbacks cannot edit while loading or application focus disables authoring")
	game.model_tool.update(0.0,true)
	var before: PackedByteArray = game.structures.capture_snapshot()
	var density: int = game.terrain.density_revision
	editor_key(KEY_RIGHT)
	var moved: PackedFloat32Array = collection.get_instance(id)
	check(is_equal_approx(moved[3],original[3]+0.5) and moved[7]==original[7] and moved[11]==original[11],"arrow input moves selected model by half a metre on world X")
	check(game.model_tool.picked_id==id and game.structures.capture_snapshot()!=before,"own transform edit retains selection and invalidates compound save cache")
	editor_key(KEY_R)
	var rotated: PackedFloat32Array = collection.get_instance(id)
	check(rotated!=moved and rotated[3]==moved[3] and rotated[7]==moved[7] and rotated[11]==moved[11],"R rotates selected model around its origin")
	editor_key(KEY_EQUAL)
	var scaled: PackedFloat32Array = collection.get_instance(id)
	check(is_equal_approx(Vector3(scaled[0],scaled[4],scaled[8]).length(),Vector3(rotated[0],rotated[4],rotated[8]).length()*1.1),"plus input scales the selected model by ten percent")
	var fine := InputEventKey.new()
	fine.physical_keycode=KEY_PAGEUP
	fine.shift_pressed=true
	fine.pressed=true
	game._unhandled_input(fine)
	var lifted: PackedFloat32Array = collection.get_instance(id)
	check(is_equal_approx(lifted[7],scaled[7]+0.1),"Shift plus Page Up provides a tenth-metre height adjustment")
	check(game.terrain.density_revision==density,"model transforms leave terrain density unchanged")
	check(await until(func(): return collection.collision_stats().pending_bodies==0 and not collection.collision_stats().selection_pending),"transformed model physics finishes bounded admission")
	var current: Transform3D = game.model_tool.selected_transform().transform
	var selected_post: Vector3 = current*Vector3(-1.5,1,0)
	var query := PhysicsRayQueryParameters3D.create(selected_post+Vector3.UP*8,selected_post-Vector3.UP*1,2)
	query.exclude=[game.player.get_rid()]
	var hit := game.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and hit.collider==collection and collection.placement_for_body(hit.rid)==id,"transformed collision still resolves the same selected ID")
	game.model_tool.refresh()
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/model_transform_editor.png")
	var outside: Vector3 = game.player.position
	game.player.position=selected_post+Vector3(0.5,-0.8,0)
	var steps: int = game.model_tool.history.stats().undo_steps
	check(not game.model_tool.transform_selected(Vector3(0.5,0,0),0.0,1.0) and collection.get_instance(id)==lifted,"native transform edit rejects moving a post through the player")
	check(game.model_tool.history.stats().undo_steps==steps,"rejected model transform adds no history command")
	game.player.position=outside
	var undo := InputEventKey.new()
	undo.physical_keycode=KEY_Z
	undo.ctrl_pressed=true
	undo.pressed=true
	game._unhandled_input(undo)
	check(game.model_tool.picked_id==0 and not game.model_tool.transform_controls.visible,"undo clears selection before an authored record can be reused")
	for i in range(3):
		game._unhandled_input(undo)
	check(collection.get_instance(id)==original and game.structures.capture_snapshot()==before,"four transform undos restore exact original placement and world snapshot")
	check(await until(func(): return collection.collision_stats().pending_bodies==0 and not collection.collision_stats().selection_pending),"undo restores original selectable model collision")
	game.player.position=aim+Vector3(6,3,6)
	game.camera.look_at(aim)
	editor_key(KEY_E)
	check(game.model_tool.picked_id==id,"restored model can be selected again")
	editor_key(KEY_Q)
	check(game.model_tool.picked_id==0,"Q explicitly returns from selection to placement")
	editor_key(KEY_E)
	var saved: PackedByteArray = collection.capture_snapshot()
	collection.restore_snapshot(saved)
	check(game.model_tool.picked_id==0,"even an identical collection reload invalidates editor selection")
	# Restore the original placement as a fresh journal command for the caller's
	# placement/removal undo sequence, after deliberately invalidating the timeline.
	collection.remove_instances(PackedInt64Array([id]))
	var replaced: int = game.model_tool.history.insert(collection,original)
	check(replaced==id,"post-reload fixture reestablishes original stable placement ID")
	await until(func(): return collection.collision_stats().pending_bodies==0 and not collection.collision_stats().selection_pending)

func check_prefab_editor(location: Vector3) -> void:
	check(game.structure_prefabs.size()==4,"editor loads reusable cottage, stair, wall and tower-floor assets")
	if game.structure_prefabs.size()!=4:
		return
	var ground := game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(location+Vector3.UP*64,location-Vector3.UP*64,1))
	check(not ground.is_empty(),"prefab site has terrain collision")
	if ground.is_empty():
		return
	game.fly=true
	game.player.position=ground.position+Vector3(0,30,0)
	game.player.velocity=Vector3.ZERO
	game.camera.look_at(ground.position,Vector3.FORWARD)
	game.structure_prefab_index=-1
	var select := InputEventKey.new()
	select.physical_keycode=KEY_P
	select.pressed=true
	game._unhandled_input(select)
	check(game.structure_prefab_index==0,"P selects the cottage asset in block mode")
	var turn := InputEventKey.new()
	turn.physical_keycode=KEY_R
	turn.pressed=true
	game.structure_rotation=0
	game._unhandled_input(turn)
	check(game.structure_rotation==1,"R rotates prefab orientation")
	var picked: Dictionary = game._structure_target(false)
	check(not picked.is_empty(),"prefab tool picks an actual construction anchor")
	if picked.is_empty():
		return
	var anchor: Vector3i = picked.target
	var asset: Resource = game.structure_prefabs[0]
	game._update_prefab_preview(1.0)
	check(game.prefab_preview.visible and game._prefab_allowed(asset,anchor),"clear prefab placement displays a valid bounds preview")
	var bounds: AABB = asset.placement_bounds(anchor,1)
	check(game.prefab_preview.position==bounds.position and game.prefab_preview.scale==bounds.size,"preview follows rotated prefab bounds")
	var outside: Vector3 = game.player.position
	game.player.position=Vector3(anchor)+Vector3(0.5,1,0.5)
	check(not game._prefab_allowed(asset,anchor),"prefab authoring rejects enclosing the player")
	game.player.position=outside
	var density_revision: int = game.terrain.density_revision
	var before_cells: int = game.structures.blocks.stats().cells
	game._edit_structure(false)
	check(game._prefab_preview_signature.is_empty(),"logical world changes invalidate cached placement validation")
	check(game.structures.blocks.stats().cells==before_cells+asset.get_cell_count(),"actual placement tool creates every cottage cell in one operation")
	check(game.terrain.density_revision==density_revision,"prefab placement leaves terrain density unchanged")
	check(not game._prefab_allowed(asset,anchor),"occupied prefab footprint is rejected")
	var cottage_snapshot: PackedByteArray = game.structures.blocks.capture_snapshot()
	var undo_key := InputEventKey.new()
	undo_key.physical_keycode=KEY_Z
	undo_key.ctrl_pressed=true
	undo_key.pressed=true
	game._unhandled_input(undo_key)
	check(game.structures.blocks.stats().cells==before_cells,"Ctrl+Z removes the entire prefab in one step")
	game.player.position=Vector3(anchor)+Vector3(0.5,0.1,0.5)
	var redo_key := InputEventKey.new()
	redo_key.physical_keycode=KEY_Y
	redo_key.ctrl_pressed=true
	redo_key.pressed=true
	game._unhandled_input(redo_key)
	check(game.structures.blocks.stats().cells==before_cells and game.structures.blocks.can_redo(),"editor redo cannot restore the prefab through the player")
	game.player.position=outside
	undo_key.shift_pressed=true
	game._unhandled_input(undo_key)
	check(game.structures.blocks.capture_snapshot()==cottage_snapshot,"Ctrl+Shift+Z restores the complete prefab after moving clear")
	check(await until(func(): return game.structures.blocks.is_idle(),20),"prefab chunk meshes finish their bounded bake queue")
	await physics_frame
	await physics_frame
	game.player.position=Vector3(anchor)+Vector3(0.5,3,0.5)
	game.player.velocity=Vector3.ZERO
	game.fly=false
	for i in range(120):
		await physics_frame
	check(game.player.is_on_floor() and game.player.position.y>anchor.y+0.9 and game.player.position.y<anchor.y+1.2,"existing player stands inside the prefab on its timber floor")
	var saved: PackedByteArray = game.structures.capture_snapshot()
	var snapshot: PackedByteArray = game.structures.blocks.capture_snapshot()
	check(game.structures.restore_snapshot(saved) and game.structures.blocks.capture_snapshot()==snapshot,"compound world restoration preserves prefab-authored cells")
	check(not game.structures.blocks.can_undo() and not game.structures.blocks.can_redo(),"world restoration clears the prior editor history")
	check(game.model_tool.history.stats().undo_steps==0 and game.model_tool.history.stats().redo_steps==0,"compound world restoration also invalidates model history")
	check(await until(func(): return game.structures.blocks.is_idle() and game.ecosystem._reconcile.is_empty(),20),"prefab reload finishes meshes and forest exclusion")
	var tower_asset: Resource = game.structure_prefabs[3]
	var tower_anchor := anchor+Vector3i(30,0,-10)
	var tower_ground := game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(tower_anchor)+Vector3.UP*64,Vector3(tower_anchor)-Vector3.UP*64,1))
	check(not tower_ground.is_empty(),"tower site has terrain collision")
	if not tower_ground.is_empty():
		tower_anchor.y=floori(tower_ground.position.y)+1
		var tower_ok := true
		var tower_before: int = game.structures.blocks.stats().cells
		for level in range(12):
			tower_ok=game.structures.blocks.place_prefab(tower_asset,tower_anchor+Vector3i(0,level*4,0),0) and tower_ok
		check(tower_ok and game.structures.blocks.stats().cells==tower_before+tower_asset.get_cell_count()*12,"twelve repeated tower floors interlock without overwriting cells")
		game.structures.blocks.set_focus(Vector3(tower_anchor)+Vector3(0,24,0))
		check(await until(func(): return game.structures.blocks.is_idle() and game.ecosystem._reconcile.is_empty(),30),"tower geometry and vegetation exclusion finish")
		game.player.position=Vector3(tower_anchor)+Vector3(3.5,27,4.5)
		game.player.velocity=Vector3.ZERO
		game.fly=false
		for i in range(120):
			await physics_frame
		check(game.player.is_on_floor() and absf(game.player.position.y-(tower_anchor.y+25.0))<0.2,"player collision works on an upper repeated tower floor")
		var stairs_ok := true
		for step in range(4):
			var tread := Vector3(tower_anchor)+Vector3(0.5,25.25+step,0.125+step)
			var tread_hit := game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(tread+Vector3.UP*0.2,tread-Vector3.UP*0.5,2))
			stairs_ok=stairs_ok and not tread_hit.is_empty() and absf(tread_hit.position.y-tread.y)<0.01
		check(stairs_ok,"repeated tower stair flights preserve their four rises through the floor shaft")
	game.fly=true
	game.structure_prefab_index=-1
	var travel_start: Vector3 = game.player.position
	var travel_models: Node3D = game.structures.model("architecture/metal_beam/v1")
	check(await until(func(): return not travel_models.render_stats().selection_pending and travel_models.render_stats().pending_batches==0 and travel_models.stats().slot_entries>0),"main world admits nearby static model rendering")
	var model_save: PackedByteArray = travel_models.capture_snapshot()
	var model_slots: int = travel_models.stats().slot_entries
	var travel_data: PackedByteArray = game.structures.blocks.capture_snapshot()
	var travel_meshes: int = game.structures.blocks.stats().mesh_chunks
	var travel_jobs: int = game.structures.blocks.streaming_stats().bake_jobs
	var travel_evidence := {"before":{"streaming":game.structures.blocks.streaming_stats(),"world":game.structures.blocks.stats()}}
	game.player.position=travel_start+Vector3(900,100,0)
	game.player.velocity=Vector3.ZERO
	check(await until(func(): return game.structures.blocks.is_idle() and game.structures.blocks.stats().mesh_chunks==0,20),"main-world travel evicts distant building meshes")
	check(game.structures.blocks.stats().collision_chunks==0 and game.structures.blocks.capture_snapshot()==travel_data,"travel releases building physics without changing saved cells")
	check(await until(func(): return travel_models.render_stats().resident_transform_bytes==0 and travel_models.stats().slot_entries==0),"main-world travel evicts distant static model rendering")
	check(travel_models.capture_snapshot()==model_save,"model render eviction leaves authored save unchanged")
	travel_evidence["away"]={"streaming":game.structures.blocks.streaming_stats(),"world":game.structures.blocks.stats()}
	game.player.position=travel_start
	check(await until(func(): return game.structures.blocks.is_idle() and game.structures.blocks.stats().mesh_chunks==travel_meshes,20),"return travel restores building meshes from cache")
	check(game.structures.blocks.streaming_stats().bake_jobs==travel_jobs,"return travel needs no additional building bake jobs")
	check(await until(func(): return travel_models.stats().slot_entries==model_slots),"return travel restores static model render residency")
	travel_evidence["returned"]={"streaming":game.structures.blocks.streaming_stats(),"world":game.structures.blocks.stats()}
	game.player.position=Vector3(anchor)+Vector3(18,13,18)
	game.player.velocity=Vector3.ZERO
	game.camera.look_at(Vector3(anchor)+Vector3(0,3,0))
	await create_timer(1.0).timeout
	if DisplayServer.get_name()!="headless":
		check(Presentation.measurement(root).fair_graphical_sample,"prefab evidence is 1920x1080 fullscreen at full scale")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/prefab_world.png")
		game.player.position=Vector3(tower_anchor)+Vector3(36,28,38)
		game.camera.look_at(Vector3(tower_anchor)+Vector3(0,24,0))
		await create_timer(3.0).timeout
		var intervals: Array[float] = []
		var previous := Time.get_ticks_usec()
		for i in range(240):
			await process_frame
			var now := Time.get_ticks_usec()
			intervals.append((now-previous)/1000.0)
			previous=now
		intervals.sort()
		var measurement: Dictionary = Presentation.measurement(root)
		measurement["stationary_frame_intervals_ms"]={"samples":intervals.size(),"median":intervals[120],"p95":intervals[228],"maximum":intervals[-1]}
		measurement["blocks"]=game.structures.blocks.stats()
		measurement["building_travel"]=travel_evidence
		measurement["trees"]=game.vegetation.renderer.roots.size()
		measurement["scope"]="Stationary presentation intervals after 3 s warmup; integrated terrain/forest with one twelve-storey tower and cottage; not isolated GPU timing or a city benchmark."
		var performance_file := FileAccess.open("res://reports/prefab_performance.json",FileAccess.WRITE)
		performance_file.store_string(JSON.stringify(measurement,"  "))
		performance_file.close()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/tower_prefab_world.png")

func finish() -> void:
	game.terrain.shutdown()
	game.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/structure_world.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	file.close()
	quit(1 if failures else 0)
