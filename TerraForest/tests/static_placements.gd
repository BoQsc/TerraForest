extends SceneTree
var checks := 0
var failures := 0
var gpu := DisplayServer.get_name() != "headless"
var collision_evidence := {}
var render_page_evidence := {}

func check(value: bool, description: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print(("PASS " if value else "FAIL ")+description)

func transform_at(x: float, y := 0.0, z := 0.0) -> PackedFloat32Array:
	return PackedFloat32Array([1,0,0,x,0,1,0,y,0,0,1,z])

func settle_render(world: Node3D) -> void:
	for i in range(120):
		await process_frame
		if not world.render_stats().selection_pending and world.render_stats().pending_batches==0:
			return
	check(false,"render residency settles within bounded test frames")

func check_render_streaming() -> void:
	var world: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(world)
	world.configure_asset("tests/render_streaming",BoxMesh.new())
	world.upsert_instances(PackedInt64Array([1,2,3]),transform_at(0)+transform_at(64)+transform_at(128))
	var saved: PackedByteArray = world.capture_snapshot()
	check(not world.render_stats().enabled and world.stats().spatial_batches==3,"unconfigured model rendering preserves eager compatibility")
	check(world.configure_render_streaming(true,256,2,96,1,48),"native rendering accepts explicit residency and upload budgets")
	check(world.stats().spatial_batches==0 and world.render_stats().resident_transform_bytes==0,"streaming reconfiguration immediately releases old buffers")
	var bounded := true
	for i in range(5):
		var before: Dictionary = world.render_stats()
		var frame := Engine.get_process_frames()
		var uploads: int = world.stats().batch_uploads
		await process_frame
		var elapsed := Engine.get_process_frames()-frame
		var after: Dictionary = world.render_stats()
		bounded=bounded and after.resident_transform_bytes<=96 and after.resident_batches<=2 and after.uploaded_transform_bytes-before.uploaded_transform_bytes<=elapsed*48 and world.stats().batch_uploads-uploads<=elapsed
	check(bounded,"renderer obeys resident bytes, batch count, upload bytes and upload count")
	check(world.stats().slot_entries==2 and world.render_stats().budget_deferred==1,"only admitted placements retain GPU slot entries")
	check(world.capture_snapshot()==saved,"render residency preserves the exact authored snapshot")
	var queries: int = world.render_stats().selection_queries
	world.set_render_focus(Vector3(0.1,0,0))
	await process_frame
	await process_frame
	check(world.render_stats().selection_queries==queries,"sub-threshold travel does not rescan stationary model groups")
	world.set_render_focus(Vector3(128,0,0))
	await settle_render(world)
	var positions: Array = []
	for child in world.get_children(): positions.append(child.position.x)
	check(positions.has(128.0) and positions.has(64.0) and not positions.has(0.0),"travel chooses nearest batches and evicts distant render buffers")
	world.upsert_instances(PackedInt64Array([1]),transform_at(-256))
	await settle_render(world)
	check(world.stats().slot_entries==2 and world.get_instance(1)[3]==-256,"nonresident model edits preserve data without allocating a distant buffer")
	world.set_render_focus(Vector3(-256,0,0))
	await settle_render(world)
	var rendered := false
	for child in world.get_children():
		if child.position.x==-256.0: rendered=not gpu or child.multimesh.get_instance_transform(0).origin.x==0.0
	check(rendered,"return travel uploads the latest nonresident placement transform")
	var edited_uploads: int = world.stats().batch_uploads
	world.upsert_instances(PackedInt64Array([1]),transform_at(-255))
	check(world.stats().spatial_batches==0,"resident transform edits queue their replacement within upload budgets")
	await settle_render(world)
	check(world.stats().batch_uploads==edited_uploads+1 and world.get_instance(1)[3]==-255 and world.stats().slot_entries==1,"resident edit republishes one current group")
	if gpu:
		check(world.get_child(0).multimesh.get_instance_transform(0).origin.x==1.0,"GPU readback contains the republished resident transform")
	check(world.restore_snapshot(saved),"streamed collection restores its authoritative snapshot")
	world.set_render_focus(Vector3.ZERO)
	await settle_render(world)
	check(world.stats().slot_entries==2 and world.capture_snapshot()==saved,"snapshot restore reconstructs only admitted batches")
	var invalid_before: Dictionary = world.render_stats()
	check(not world.configure_render_streaming(true,NAN,2,96,1,48) and not world.configure_render_streaming(true,32,0,96,1,48) and not world.configure_render_streaming(true,32,2,47,1,48) and not world.configure_render_streaming(true,32,2,96,0,48) and not world.configure_render_streaming(true,32,2,96,1,47),"invalid render configurations reject atomically")
	world.set_render_focus(Vector3(NAN,0,0))
	check(world.render_stats()==invalid_before,"invalid budget and focus leave render state unchanged")
	world.configure_render_streaming(true,256,2,96,2,48)
	world.upsert_instances(PackedInt64Array([4]),transform_at(1))
	await settle_render(world)
	check(world.render_stats().budget_deferred==2 and world.stats().slot_entries==2 and world.render_stats().page_capacity==1,"tiny upload budget splits dense nearest group into admissible pages")
	var nearest_pages := true
	for child in world.get_children(): nearest_pages=nearest_pages and child.position.x==0.0
	check(nearest_pages and world.get_instance(4).size()==12,"nearest dense-group pages render while farther placements stay authored")
	world.remove_instances(PackedInt64Array([1,4]))
	await settle_render(world)
	check(world.stats().slot_entries==2 and world.render_stats().resident_transform_bytes==96,"removal reclaims memberships without stale slots")
	root.remove_child(world)
	check(world.render_stats().resident_transform_bytes==0 and world.stats().slot_entries==0,"tree exit releases streamed rendering and slot membership")
	root.add_child(world)
	await settle_render(world)
	check(world.stats().slot_entries==2,"tree reentry restores eligible rendering")
	world.configure_render_streaming(false,256,2,96,1,48)
	check(world.stats().slot_entries==world.stats().instances,"disabling streaming restores eager rendering")
	world.queue_free()
	await process_frame
	await check_render_bounds()
	await check_render_population()
	await check_dense_render_pages()

func check_render_bounds() -> void:
	var world: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(world)
	world.configure_asset("tests/extended_mesh",BoxMesh.new())
	world.configure_render_streaming(true,4,4,192,1,96)
	var long_model := transform_at(100)
	long_model[0]=200
	world.upsert_instances(PackedInt64Array([1]),long_model)
	world.configure_collision(AABB(Vector3(-0.1,-0.1,-0.1),Vector3.ONE*0.2),4,1,1)
	await settle_render(world)
	await settle_collision(world)
	check(world.stats().slot_entries==1 and world.collision_stats().resident_bodies==0,"render admission uses mesh extent independently of smaller collision proxies")
	var expanded := BoxMesh.new()
	expanded.size=Vector3(0.1,1,1)
	world.configure_asset("tests/extended_mesh",expanded)
	await settle_render(world)
	check(world.stats().slot_entries==0,"asset mesh bounds changes invalidate render residency")
	world.set_render_focus(Vector3(100,0,0))
	world.set_collision_focus(Vector3(100,0,0))
	await settle_render(world)
	await settle_collision(world)
	var hit := collision_ray(Vector3(100,3,0),Vector3(100,-3,0))
	world.set_render_focus(Vector3(10000,0,0))
	await settle_render(world)
	check(world.stats().slot_entries==0 and not hit.is_empty() and world.collision_stats().resident_bodies==1,"render eviction does not change independently admitted physics")
	var occupancy: PackedByteArray = world.overlap_mask([Transform3D(Basis(),Vector3(100,0,0))],AABB(Vector3(-0.1,-0.1,-0.1),Vector3.ONE*0.2))
	check(occupancy.size()==1 and occupancy[0]==1,"nonresident rendering still excludes vegetation from authored geometry")
	world.queue_free()
	await process_frame

func check_render_population() -> void:
	var world: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(world)
	world.configure_asset("tests/100k_streaming",BoxMesh.new())
	world.configure_render_streaming(true,80,2,96000,1,48000)
	var ids := PackedInt64Array()
	var transforms := PackedFloat32Array()
	ids.resize(100000)
	transforms.resize(1200000)
	for i in range(100000):
		ids[i]=i+1
		var offset := i*12
		transforms[offset]=1
		transforms[offset+3]=float(i/1000)*64
		transforms[offset+5]=1
		transforms[offset+7]=float((i%1000)/32)
		transforms[offset+10]=1
		transforms[offset+11]=i%32
	check(world.upsert_instances(ids,transforms),"100000 placements enter authored storage with deferred rendering")
	var saved: PackedByteArray = world.capture_snapshot()
	await settle_render(world)
	check(world.stats().instances==100000 and world.render_stats().authored_groups==100 and world.stats().slot_entries==2000 and world.render_stats().resident_transform_bytes==96000,"100000 placements retain only 2000 nearby render transforms under 96 KB payload budget")
	var stable := true
	for cycle in range(20):
		world.set_render_focus(Vector3((cycle%2)*6336,0,0))
		await settle_render(world)
		stable=stable and world.render_stats().resident_transform_bytes<=96000 and world.stats().slot_entries<=2000 and world.get_child_count()<=2
	check(stable and world.capture_snapshot()==saved,"repeated end-to-end travel bounds rendering without altering 100000 placements")
	world.remove_instances(ids)
	await settle_render(world)
	check(world.get_child_count()==0 and world.stats().slot_entries==0 and world.render_stats().resident_transform_bytes==0 and world.render_stats().authored_groups==0,"clearing the population releases all render buffers, bounds and slots")
	world.queue_free()
	await process_frame

func check_dense_render_pages() -> void:
	var world: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(world)
	var mesh := BoxMesh.new()
	mesh.size=Vector3.ONE*0.3
	world.configure_asset("tests/dense_render_pages",mesh)
	check(world.configure_render_streaming(true,64,128,4800000,2,49152),"dense model fixture configures one 1024-record page payload per tick")
	var ids := PackedInt64Array()
	var transforms := PackedFloat32Array()
	ids.resize(100000)
	transforms.resize(1200000)
	for i in range(100000):
		ids[i]=9000000001+i
		var offset := i*12
		transforms[offset]=1
		transforms[offset+3]=(i%46)*0.5
		transforms[offset+5]=1
		transforms[offset+7]=((i/46)%46)*0.5
		transforms[offset+10]=1
		transforms[offset+11]=(i/2116)*0.5
	check(world.upsert_instances(ids,transforms),"100000 high-ID model records fit one authored spatial group")
	var saved: PackedByteArray = world.capture_snapshot()
	check(world.render_stats().authored_groups==1 and world.render_stats().indexed_instances==100000 and world.stats().slot_entries==0,"dense authoring builds its ordered index without immediate renderer uploads")
	var bounded := true
	var observed := 0
	for i in range(120):
		var before: Dictionary = world.render_stats()
		var frame := Engine.get_process_frames()
		var uploads: int = world.stats().batch_uploads
		await process_frame
		var elapsed := Engine.get_process_frames()-frame
		var after: Dictionary = world.render_stats()
		bounded=bounded and after.uploaded_transform_bytes-before.uploaded_transform_bytes<=elapsed*49152 and world.stats().batch_uploads-uploads<=elapsed*2 and after.resident_transform_bytes<=4800000 and after.resident_batches<=128
		observed+=1
		if not after.selection_pending and after.pending_batches==0: break
	check(bounded and observed>1,"dense group loads across frames within upload and residency ceilings")
	check(world.stats().slot_entries==100000 and world.get_child_count()==98 and world.render_stats().budget_deferred==0,"all 100000 dense placements become render resident across 98 pages")
	var page_sizes := true
	var total := 0
	var exact := true
	for child in world.get_children():
		var count: int = child.multimesh.instance_count
		page_sizes=page_sizes and count<=1024 and count>0
		if gpu:
			for slot in [0,count-1]:
				var index: int = (total+slot)*12
				var expected := Vector3(transforms[index+3],transforms[index+7],transforms[index+11])
				exact=exact and child.multimesh.get_instance_transform(slot).origin.is_equal_approx(expected)
		total+=count
	check(page_sizes and total==100000,"dense render pages have bounded size and complete record coverage")
	if gpu: check(exact,"GPU first/last record readback matches every dense render page")
	check(world.capture_snapshot()==saved,"dense render paging does not change snapshot format or bytes")
	render_page_evidence={"dense":world.render_stats(),"observed_process_frames":observed,"gpu_page_readback":gpu}
	var untouched: int = world.get_child(1).get_instance_id()
	var prior_uploads: int = world.stats().batch_uploads
	var local_edit := transforms.slice(0,12)
	local_edit[3]=0.25
	check(world.upsert_instances(PackedInt64Array([ids[0]]),local_edit),"edit one transform within a dense origin group")
	check(world.get_child_count()==97 and world.stats().slot_entries==98976,"same-group edit evicts only its 1024-instance page")
	await settle_render(world)
	check(world.stats().batch_uploads==prior_uploads+1 and world.stats().slot_entries==100000 and is_instance_id_valid(untouched),"dense local edit republishes one page and retains unrelated render nodes")
	if gpu: check(world.get_child(97).multimesh.get_instance_transform(0).origin.x==0.25,"GPU readback reflects the updated dense page")
	world.upsert_instances(PackedInt64Array([ids[0]]),transforms.slice(0,12))
	await settle_render(world)
	check(world.stats().batch_uploads==prior_uploads+2 and world.capture_snapshot()==saved,"reversing dense local edit preserves every other page and original snapshot")
	world.configure_render_streaming(true,64,4,130560,2,49152)
	await settle_render(world)
	check(world.stats().slot_entries==2720 and world.get_child_count()==3 and world.render_stats().budget_deferred==95,"partial final page fills remaining resident budget after two full pages")
	if gpu:
		var tail: MultiMesh = world.get_child(2).multimesh
		var index := 99328*12
		check(tail.instance_count==672 and tail.get_instance_transform(0).origin.is_equal_approx(Vector3(transforms[index+3],transforms[index+7],transforms[index+11])),"GPU partial-page readback uses the correct noncontiguous page offset")
	world.configure_render_streaming(true,64,5,240,1,48)
	await settle_render(world)
	check(world.render_stats().page_capacity==1 and world.stats().slot_entries==5 and world.render_stats().candidate_batches==100000 and world.render_stats().budget_deferred==99995,"tiny upload budget admits dense records without requiring a whole group upload")
	check(world.get_child_count()==5 and world.render_stats().resident_transform_bytes==240,"tiny-budget dense fixture never allocates invisible overflow render nodes")
	render_page_evidence["tiny_budget"]=world.render_stats()
	var queries: int = world.render_stats().selection_queries
	await process_frame
	await process_frame
	check(world.render_stats().selection_queries==queries,"settled dense pages do not rescan while stationary")
	world.configure_render_streaming(true,64,128,4800000,2,49152)
	await process_frame
	await process_frame
	check(world.stats().slot_entries>0 and world.render_stats().pending_batches>0,"mutation fixture has both resident and pending dense pages")
	check(world.remove_instances(ids.slice(0,2000)),"remove dense records while old pages are still queued")
	check(world.stats().slot_entries==0,"dense membership change discards obsolete page slots before republication")
	await settle_render(world)
	check(world.stats().slot_entries==98000 and world.render_stats().indexed_instances==98000 and world.get_child_count()==96,"queued dense pages rebuild from current membership without removed records")
	check(world.restore_snapshot(saved),"dense page fixture restores its saved high-ID records")
	await settle_render(world)
	var moved := transforms.slice(0,12)
	moved[3]=-1
	check(world.upsert_instances(PackedInt64Array([ids[0]]),moved),"move one dense-page record across a signed origin-group boundary")
	await settle_render(world)
	check(world.stats().slot_entries==100000 and world.render_stats().indexed_instances==100000 and world.render_stats().authored_groups==2 and world.get_child_count()==99,"cross-group dense move retains unique complete render slot membership")
	world.set_render_focus(Vector3(1000,0,0))
	await settle_render(world)
	check(world.get_child_count()==0 and world.stats().slot_entries==0 and world.render_stats().resident_transform_bytes==0,"travel evicts every dense page and its derived slot mappings")
	world.set_render_focus(Vector3.ZERO)
	await settle_render(world)
	check(world.stats().slot_entries==100000 and world.get_child_count()==99,"return travel restores dense pages within the same bounded scheduler")
	world.remove_instances(ids)
	await settle_render(world)
	check(world.render_stats().indexed_instances==0 and world.render_stats().index_capacity_bytes==0 and world.get_child_count()==0 and world.stats().slot_entries==0,"clearing dense data releases the ordered index and all render pages")
	world.queue_free()
	await process_frame

func signed_snapshot(payload: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(payload)
	payload.append_array(hash.finish())
	return payload

func _initialize() -> void:
	if not ClassDB.class_exists("NativeStaticBatch"):
		GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	run.call_deferred()

func settle_collision(world: Node3D) -> void:
	for i in range(30):
		await physics_frame
		await process_frame
		var status: Dictionary = world.collision_stats()
		if not status.selection_pending and status.pending_bodies==0:
			break
	await physics_frame
	await process_frame

func collision_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from,to,2)
	return root.get_world_3d().direct_space_state.intersect_ray(query)

func check_collision() -> void:
	var world: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(world)
	world.configure_asset("tests/collision_box",BoxMesh.new())
	var box := AABB(Vector3(-0.5,-0.5,-0.5),Vector3.ONE)
	check(not world.collision_stats().enabled,"static collision defaults to opt-in")
	world.upsert_instances(PackedInt64Array([17,9000000001,33]),transform_at(0)+transform_at(8)+transform_at(80))
	var saved: PackedByteArray = world.capture_snapshot()
	check(world.configure_collision(box,16,2,1),"configure bounded native static collision")
	check(not world.is_collision_region_ready(box),"authored model blocks readiness before its collider is admitted")
	check(world.is_collision_region_ready(AABB(Vector3(3,-0.5,-0.5),Vector3.ONE)),"empty space within a model origin group remains ready")
	check(not world.is_collision_region_ready(AABB(Vector3.ZERO,Vector3.ZERO)),"model readiness rejects degenerate query bounds")
	var bounded := true
	var previous: int = world.collision_stats().body_builds
	var previous_tick := Engine.get_physics_frames()
	for i in range(5):
		await physics_frame
		await process_frame
		var now: int = world.collision_stats().body_builds
		bounded=bounded and now-previous<=Engine.get_physics_frames()-previous_tick
		previous=now
		previous_tick=Engine.get_physics_frames()
	check(bounded and world.collision_stats().resident_bodies==2,"nearby proxies publish within one-body-per-tick budget")
	check(world.is_collision_region_ready(box),"resident model collision satisfies local readiness")
	check(not world.is_collision_region_ready(AABB(Vector3(79.5,-0.5,-0.5),Vector3.ONE)),"distant authored model stays unready when its collider is absent")
	world.position=Vector3(100,0,0)
	check(not world.is_collision_region_ready(AABB(Vector3(99.5,-0.5,-0.5),Vector3.ONE)),"collection transform change rejects stale collision immediately")
	world.position=Vector3.ZERO
	check(world.get_child_count()==world.stats().spatial_batches,"native collision adds no per-placement scene nodes")
	var hit := collision_ray(Vector3(8,3,0),Vector3(8,-3,0))
	check(not hit.is_empty() and hit.collider==world and world.placement_for_body(hit.rid)==9000000001,"physics ray resolves exact stable 64-bit placement ID")
	check(collision_ray(Vector3(80,3,0),Vector3(80,-3,0)).is_empty(),"distant static placements have no physics body")
	check(world.capture_snapshot()==saved,"collision residency does not change placement snapshots")
	var corrupt := saved.duplicate()
	corrupt[40]^=1
	var invalid := transform_at(3)
	invalid[0]=NAN
	var builds_before: int = world.collision_stats().body_builds
	check(not world.restore_snapshot(corrupt) and not world.upsert_instances(PackedInt64Array([17]),invalid),"invalid load and edit reject before changing physics")
	await settle_collision(world)
	check(world.collision_stats().body_builds==builds_before and world.collision_stats().resident_bodies==2,"rejected commands preserve existing physics handles")
	var queries: int = world.collision_stats().selection_queries
	world.set_collision_focus(Vector3(0.1,0,0))
	await settle_collision(world)
	check(world.collision_stats().selection_queries==queries,"small focus changes avoid repeated placement scans")
	check(not world.configure_collision(box,NAN,2,1) and not world.configure_collision(box,16,0,1) and not world.configure_collision(box,16,2,0),"invalid budgets preserve collision configuration")
	check(not world.configure_collision(AABB(Vector3.ZERO,Vector3(-1,1,1)),16,2,1),"invalid proxy geometry rejected")
	check(world.collision_stats().resident_bodies==2 and world.collision_stats().radius==16,"invalid configuration preserves existing collision")
	world.set_collision_focus(Vector3(80,0,0))
	await settle_collision(world)
	check(world.collision_stats().resident_bodies==1 and collision_ray(Vector3(8,3,0),Vector3(8,-3,0)).is_empty(),"travel evicts old bodies and admits the nearby placement")
	hit=collision_ray(Vector3(80,3,0),Vector3(80,-3,0))
	check(not hit.is_empty() and world.placement_for_body(hit.rid)==33,"travelled-to object has its own collision identity")
	world.set_collision_focus(Vector3.ZERO)
	await settle_collision(world)
	var stale_rid: RID = collision_ray(Vector3(8,3,0),Vector3(8,-3,0)).rid
	world.upsert_instances(PackedInt64Array([9000000001]),transform_at(12))
	check(world.placement_for_body(stale_rid)==0,"moving a placement immediately invalidates its old physics identity")
	await settle_collision(world)
	check(collision_ray(Vector3(8,3,0),Vector3(8,-3,0)).is_empty() and not collision_ray(Vector3(12,3,0),Vector3(12,-3,0)).is_empty(),"local render edit also moves static collision")
	world.remove_instances(PackedInt64Array([9000000001]))
	await settle_collision(world)
	check(collision_ray(Vector3(12,3,0),Vector3(12,-3,0)).is_empty(),"removal releases collision")
	check(world.restore_snapshot(saved),"restore collidable placements")
	await settle_collision(world)
	check(not collision_ray(Vector3(8,3,0),Vector3(8,-3,0)).is_empty(),"snapshot restore rebuilds application-configured proxies")
	# A large scaled proxy crosses several origin groups; selection uses its bounds.
	world.upsert_instances(PackedInt64Array([44]),PackedFloat32Array([100,0,0,65,0,1,0,0,0,0,1,0]))
	world.set_collision_focus(Vector3(20,0,0))
	await settle_collision(world)
	hit=collision_ray(Vector3(20,3,0),Vector3(20,-3,0))
	check(not hit.is_empty() and world.placement_for_body(hit.rid)==44,"large proxy crossing origin groups remains selectable by its bounds")
	check(world.configure_collision(box,128,1,1),"collision count cap can shrink")
	await settle_collision(world)
	check(world.collision_stats().resident_bodies==1 and world.collision_stats().budget_deferred==3,"nearest admission reports capacity-deferred collision")
	world.restore_snapshot(saved)
	world.configure_collision(box,16,2,2)
	world.set_collision_focus(Vector3.ZERO)
	# Nonuniform scale and shear are baked into convex vertices, not body scale.
	world.upsert_instances(PackedInt64Array([17]),PackedFloat32Array([2,0.5,0,0,0,2,0,0,0,0,3,0]))
	await settle_collision(world)
	hit=collision_ray(Vector3(0,3,0),Vector3(0,-3,0))
	check(not hit.is_empty() and absf(hit.position.y-1.0)<0.02,"affine placement basis produces matching convex proxy surface")
	world.position=Vector3(0,10,0)
	world.scale=Vector3(1,2,1)
	await settle_collision(world)
	hit=collision_ray(Vector3(0,15,0),Vector3(0,5,0))
	check(not hit.is_empty() and absf(hit.position.y-12.0)<0.02,"collection transform updates physics without scaled-body mismatch")
	root.remove_child(world)
	check(world.collision_stats().resident_bodies==0,"leaving the scene releases all native physics handles")
	root.add_child(world)
	await settle_collision(world)
	check(world.collision_stats().resident_bodies==2,"reentering the scene rebuilds collision")
	var viewport := SubViewport.new()
	viewport.own_world_3d=true
	root.add_child(viewport)
	world.reparent(viewport)
	await settle_collision(world)
	check(collision_ray(Vector3(0,15,0),Vector3(0,5,0)).is_empty(),"moving to a private physics world removes collision from the old world")
	# Retain the departing World3D through Godot's viewport scenario reassignment.
	var private_world: World3D = world.get_world_3d()
	var private_hit := private_world.direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(0,15,0),Vector3(0,5,0),2))
	check(not private_hit.is_empty() and world.placement_for_body(private_hit.rid)==17,"private physics world receives the placement proxies")
	viewport.own_world_3d=false
	await settle_collision(world)
	check(not collision_ray(Vector3(0,15,0),Vector3(0,5,0)).is_empty(),"in-tree world reassignment rebinds native bodies to the new space")
	world.reparent(root)
	viewport.free()
	check(world.configure_collision(box,0,2,2) and world.collision_stats().resident_bodies==0,"disabling collision releases bodies immediately")
	# Repeated travel checks bounded retained handles, not a long-duration benchmark.
	world.transform=Transform3D.IDENTITY
	world.restore_snapshot(saved)
	world.configure_collision(box,16,2,2)
	var travel_ok := true
	for i in range(20):
		world.set_collision_focus(Vector3.ZERO if i%2==0 else Vector3(80,0,0))
		await settle_collision(world)
		travel_ok=travel_ok and world.collision_stats().resident_bodies==(2 if i%2==0 else 1)
	check(travel_ok and world.capture_snapshot()==saved,"twenty visits retain only nearby physics and preserve authored records")
	var dense := PackedFloat32Array()
	dense.resize(100000*12)
	for i in range(100000):
		var p := transform_at((i%1000)*2,0,(i/1000)*2)
		for j in range(12):
			dense[i*12+j]=p[j]
	world.configure_collision(box,16,16,4)
	world.set_collision_focus(Vector3.ZERO)
	check(world.set_instances(BoxMesh.new(),dense),"100000 placements coexist with bounded collision configuration")
	await settle_collision(world)
	collision_evidence=world.collision_stats()
	check(collision_evidence.resident_bodies==16 and collision_evidence.budget_deferred>0 and collision_evidence.pending_bodies==0,"100000-placement collection admits only sixteen nearest physics bodies")
	check(world.get_child_count()==world.stats().spatial_batches,"large collidable collection retains only spatial render nodes")
	var dense_history: RefCounted = ClassDB.instantiate("NativeStaticHistory")
	check(dense_history.configure([world],4096,16),"100000-placement collection supports bounded native authoring history")
	var old_transform: PackedFloat32Array = world.get_instance(50000)
	var moved_transform := old_transform.duplicate()
	moved_transform[3]+=0.125
	var uploads: int = world.stats().batch_uploads
	var slot_updates: int = world.stats().instance_updates
	check(dense_history.update(world,50000,moved_transform),"native journal updates one model inside a 100000-placement collection")
	check(world.stats().batch_uploads==uploads and world.stats().instance_updates==slot_updates+1,"history keeps same-group GPU updates incremental")
	check(dense_history.stats().record_bytes==dense_history.stats().record_size,"one edit retains one fixed-size record regardless of collection population")
	check(dense_history.undo() and world.get_instance(50000)==old_transform and dense_history.redo() and world.get_instance(50000)==moved_transform,"dense collection undo and redo restore exact transform")
	collision_evidence["history"]=dense_history.stats()
	# A real character controller must stand on a scaled static model floor.
	world.set_instances(BoxMesh.new(),PackedFloat32Array([8,0,0,0,0,1,0,0,0,0,8,0]))
	world.set_collision_focus(Vector3.ZERO)
	await settle_collision(world)
	var player := CharacterBody3D.new()
	player.collision_mask=2
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius=0.25
	capsule.height=1
	shape.shape=capsule
	player.add_child(shape)
	root.add_child(player)
	player.position=Vector3(0,3,0)
	for i in range(90):
		await physics_frame
		player.velocity.y-=9.8/60.0
		player.move_and_slide()
	check(player.is_on_floor() and absf(player.position.y-1.0)<0.06,"CharacterBody3D lands on the placed model floor")
	player.free()
	world.free()
	await physics_frame
	await process_frame
	check(collision_ray(Vector3(0,3,0),Vector3(0,-3,0)).is_empty(),"destroying collection leaves no ghost physics")

func check_compound_collision() -> void:
	var world: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(world)
	var mesh: Mesh = load("res://addons/structures/prefabs/doorway_model.tres")
	var boxes: Array[AABB] = mesh.get_meta("collision_boxes").duplicate()
	world.configure_asset("architecture/doorway/v1",mesh)
	world.upsert_instances(PackedInt64Array([11,22,33]),transform_at(0)+transform_at(8)+transform_at(16))
	check(world.configure_compound_collision(boxes,64,3,8,6,3),"compound doorway uses explicit body and shape budgets")
	check(world.is_collision_region_ready(AABB(Vector3(-0.3,0.3,-0.2),Vector3(0.6,1.2,0.4))),"unbuilt compound doorway leaves its actual opening ready")
	check(not world.is_collision_region_ready(boxes[0]),"unbuilt doorway post is not collision ready")
	var before: int = world.collision_stats().body_builds
	var tick := Engine.get_physics_frames()
	var bounded := true
	for i in range(5):
		await physics_frame
		await process_frame
		var built: int = world.collision_stats().body_builds
		bounded=bounded and (built-before)*3<=(Engine.get_physics_frames()-tick)*3
		before=built
		tick=Engine.get_physics_frames()
	var status: Dictionary = world.collision_stats()
	check(bounded and status.resident_bodies==2 and status.resident_shapes==6 and status.budget_deferred==1,"shape budgets bound residency and tick publication independently of body budgets")
	check(world.is_collision_region_ready(boxes[0]),"completed compound proxy satisfies readiness")
	var deferred_part: AABB = boxes[0]
	deferred_part.position.x+=16
	check(not world.is_collision_region_ready(deferred_part),"shape-budget-deferred model remains unready even with an empty pending queue")
	check(collision_ray(Vector3(0,1,-2),Vector3(0,1,2)).is_empty(),"doorway opening is not filled by the union bounding box")
	for point in [Vector3(-1.5,1,0),Vector3(1.5,1,0),Vector3(0,2.5,0)]:
		var hit := collision_ray(point+Vector3(0,0,-2),point+Vector3(0,0,2))
		check(not hit.is_empty() and world.placement_for_body(hit.rid)==11,"each doorway part resolves to the same placement identity")
	var player := CharacterBody3D.new()
	player.collision_mask=2
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius=0.25
	capsule.height=1
	shape.shape=capsule
	player.add_child(shape)
	root.add_child(player)
	player.position=Vector3(0,1,-2)
	check(player.move_and_collide(Vector3(0,0,4))==null and player.position.z>1.9,"character passes through the compound doorway")
	player.position=Vector3(1.5,1,-2)
	check(player.move_and_collide(Vector3(0,0,4))!=null and player.position.z<0,"character is stopped by the door post")
	player.free()
	check(not world.configure_compound_collision(boxes,64,3,8,2,3) and not world.configure_compound_collision(boxes,64,3,8,6,2),"budgets too small for one complete compound body reject atomically")
	var bad: Array[AABB] = boxes.duplicate()
	bad.append(AABB(Vector3.ZERO,Vector3.ZERO))
	check(not world.configure_compound_collision(bad,64,3,8,6,3),"invalid part rejects the entire compound configuration")
	var excess: Array[AABB] = []
	for i in range(33):
		excess.append(boxes[0])
	check(not world.configure_compound_collision(excess,64,3,8,100,64),"compound part count is bounded")
	check(world.collision_stats().resident_shapes==6,"rejected compound configurations preserve live bodies")
	boxes[0]=AABB(Vector3(50,0,0),Vector3.ONE)
	world.set_collision_focus(Vector3(16,0,0))
	await settle_collision(world)
	world.set_collision_focus(Vector3.ZERO)
	await settle_collision(world)
	check(not collision_ray(Vector3(-1.5,1,-2),Vector3(-1.5,1,2)).is_empty(),"caller array mutation cannot alter retained compound metadata")
	var saved: PackedByteArray = world.capture_snapshot()
	world.remove_instances(PackedInt64Array([11]))
	await settle_collision(world)
	check(collision_ray(Vector3(-1.5,1,-2),Vector3(-1.5,1,2)).is_empty(),"removal releases every part of a compound body")
	world.restore_snapshot(saved)
	await settle_collision(world)
	check(not collision_ray(Vector3(-1.5,1,-2),Vector3(-1.5,1,2)).is_empty() and collision_ray(Vector3(0,1,-2),Vector3(0,1,2)).is_empty(),"restore reconstructs compound solids and openings")
	world.free()
	await physics_frame
	await process_frame
	check(collision_ray(Vector3(-1.5,1,-2),Vector3(-1.5,1,2)).is_empty(),"compound destruction leaves no ghost shapes")

func run() -> void:
	if gpu:
		DisplayServer.window_set_size(Vector2i(1920,1080))
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		await process_frame
		check(DisplayServer.window_get_size()==Vector2i(1920,1080) and DisplayServer.window_get_mode()==4, "GPU test uses 1920x1080 exclusive fullscreen")
		check(root.get_texture().get_size()==Vector2(1920,1080), "GPU test render target is 1920x1080")
	var world: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(world)
	var mesh := BoxMesh.new()
	check(not world.upsert_instances(PackedInt64Array([1]),transform_at(0)), "reject edits before mesh configuration")
	check(world.capture_snapshot().is_empty(), "unconfigured collection cannot silently save anonymous assets")
	check(not world.configure_asset("",mesh) and not world.configure_asset("bad key",mesh), "reject invalid asset keys")
	check(world.configure_asset("architecture/fence",mesh), "configure stable asset key")
	var empty: PackedByteArray = world.capture_snapshot()
	check(world.validate_snapshot(empty), "empty configured snapshot validates")
	var data := transform_at(-1)+transform_at(1)+transform_at(65)
	check(world.upsert_instances(PackedInt64Array([17,42,9000000001]),data), "insert explicit 64-bit stable IDs")
	check(world.get_ids()==PackedInt64Array([17,42,9000000001]), "IDs remain sorted and preserve 64-bit precision")
	check(world.get_instance(17)==transform_at(-1), "retrieve exact authored transform")
	check(world.get_instance(999).is_empty(), "missing object returns no transform")
	var far_node := world.get_child(2).get_instance_id()
	var uploads: int = world.stats().batch_uploads
	check(world.upsert_instances(PackedInt64Array([42]),transform_at(2)), "move object inside group")
	check(world.stats().batch_uploads==uploads and world.stats().instance_updates==1, "single local edit updates one GPU slot without rebuilding its group")
	var local_batch: MultiMeshInstance3D = world.get_child(1)
	if gpu:
		check(local_batch.multimesh.get_instance_transform(0).origin==Vector3(2,0,0), "GPU slot contains updated local translation")
	check(world.get_child(2).get_instance_id()==far_node, "unrelated group keeps its scene node")
	uploads = world.stats().batch_uploads
	check(world.upsert_instances(PackedInt64Array([42]),transform_at(2)) and world.stats().batch_uploads==uploads, "identical edit performs no GPU upload")
	var rotated := PackedFloat32Array([0,0,2,2,0,3,0,0,-4,0,0,0])
	check(world.upsert_instances(PackedInt64Array([42]),rotated), "direct slot update accepts rotated scaled basis")
	if gpu:
		var rendered := local_batch.multimesh.get_instance_transform(0)
		check(rendered.basis.x==Vector3(0,0,-4) and rendered.basis.y==Vector3(0,3,0) and rendered.basis.z==Vector3(2,0,0), "direct slot update preserves matrix row/column convention")
	check(world.upsert_instances(PackedInt64Array([42]),transform_at(-2)), "move existing ID across signed group boundary")
	check(world.stats().spatial_batches==2 and world.get_instance(42)==transform_at(-2), "move reclaims old empty group and preserves ID")
	var before: PackedByteArray = world.capture_snapshot()
	check(not world.upsert_instances(PackedInt64Array([17,17]),transform_at(1)+transform_at(2)), "duplicate IDs rejected")
	check(not world.upsert_instances(PackedInt64Array([0]),transform_at(1)), "zero ID rejected")
	check(not world.upsert_instances(PackedInt64Array([-1]),transform_at(1)), "negative ID rejected")
	check(not world.upsert_instances(PackedInt64Array([17]),PackedFloat32Array([1])), "incomplete transform rejected")
	var invalid := transform_at(1)
	invalid[0]=0
	check(not world.upsert_instances(PackedInt64Array([17]),invalid), "singular basis rejected")
	invalid[0]=INF
	check(not world.upsert_instances(PackedInt64Array([17]),invalid), "nonfinite basis rejected")
	check(not world.remove_instances(PackedInt64Array([17,99])), "mixed existing/missing removal rejected")
	check(not world.remove_instances(PackedInt64Array([17,17])), "duplicate removal IDs rejected")
	check(not world.configure_asset("different/mesh",mesh), "populated asset identity cannot change silently")
	check(world.capture_snapshot()==before, "all rejected commands preserve snapshot bytes")
	var copy: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(copy)
	copy.configure_asset("wrong/asset",mesh)
	check(copy.validate_snapshot(before) and not copy.restore_snapshot(before), "valid snapshot with unresolved asset identity rejected on restore")
	copy.configure_asset("architecture/fence",mesh)
	check(copy.restore_snapshot(before) and copy.capture_snapshot()==before, "asset-bound snapshot round trip preserves IDs/transforms")
	var corrupt := before.duplicate()
	corrupt[40]^=1
	check(not copy.restore_snapshot(corrupt), "checksum catches accidental corruption")
	check(not copy.restore_snapshot(before.slice(0,before.size()-1)), "truncated snapshot rejected")
	# Re-sign malicious fields to test semantic validation beyond checksum integrity.
	var first_record := 16+"architecture/fence".length()
	var payload := before.slice(0,before.size()-32)
	payload.encode_u64(first_record,0)
	check(not copy.validate_snapshot(signed_snapshot(payload)), "checksummed zero placement ID rejected")
	payload=before.slice(0,before.size()-32)
	payload.encode_u64(first_record+56,17)
	check(not copy.validate_snapshot(signed_snapshot(payload)), "checksummed duplicate placement ID rejected")
	payload=before.slice(0,before.size()-32)
	payload.encode_float(first_record+8,NAN)
	check(not copy.validate_snapshot(signed_snapshot(payload)), "checksummed NaN transform rejected")
	payload=before.slice(0,before.size()-32)
	payload.encode_u32(12,100001)
	check(not copy.validate_snapshot(signed_snapshot(payload)), "checksummed excessive count rejected before allocation")
	check(copy.capture_snapshot()==before, "rejected loads preserve published collection")
	check(world.remove_instances(PackedInt64Array([17])) and world.get_ids()==PackedInt64Array([42,9000000001]), "removal preserves all remaining IDs")
	check(world.restore_snapshot(empty) and world.get_child_count()==0, "restoring empty collection releases all render batches")
	var dense_ids := PackedInt64Array()
	var dense_transforms := PackedFloat32Array()
	var dense_moved := PackedFloat32Array()
	for i in range(100):
		dense_ids.append(i+1)
		dense_transforms.append_array(transform_at(i%16))
		dense_moved.append_array(transform_at(i%16+0.125))
	world.upsert_instances(dense_ids,dense_transforms)
	uploads=world.stats().batch_uploads
	var individual: int = world.stats().instance_updates
	check(world.upsert_instances(dense_ids,dense_moved), "large same-group update accepted")
	check(world.stats().batch_uploads==uploads+1 and world.stats().instance_updates==individual, "large edit uses one bulk upload instead of individual renderer calls")
	world.restore_snapshot(empty)
	# Maximum group count is checked against the final transaction, allowing swaps.
	var ids := PackedInt64Array()
	var transforms := PackedFloat32Array()
	for i in range(4096):
		ids.append(i+1)
		transforms.append_array(transform_at(i*32))
	check(world.upsert_instances(ids,transforms), "4096 spatial group boundary accepted")
	before=world.capture_snapshot()
	check(not world.upsert_instances(PackedInt64Array([5000]),transform_at(4096*32)), "4097th spatial group rejected atomically")
	check(world.capture_snapshot()==before, "group overflow leaves collection unchanged")
	check(world.upsert_instances(PackedInt64Array([1]),transform_at(4096*32)), "moving singleton group at capacity allowed")
	check(world.stats().spatial_batches==4096 and world.stats().instances==4096, "capacity move retains exact limits")
	world.restore_snapshot(empty)
	for i in range(1000):
		world.upsert_instances(PackedInt64Array([i+1]),transform_at(i*32))
		world.remove_instances(PackedInt64Array([i+1]))
	check(world.stats().instances==0 and world.stats().spatial_batches==0 and world.stats().slot_entries==0 and world.get_child_count()==0, "repeated placement/removal retains no spatial or slot tombstones")
	await check_collision()
	await check_compound_collision()
	var auto_world: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(auto_world)
	auto_world.configure_asset("tests/automatic_ids",BoxMesh.new())
	check(auto_world.can_insert_instance(transform_at(4)) and auto_world.get_ids().is_empty(),"native insertion preview is read-only")
	check(auto_world.insert_instance(transform_at(4))==1 and auto_world.insert_instance(transform_at(8))==2,"automatic placement IDs do not overwrite live objects")
	var protected := AABB(Vector3(11,-1,-1),Vector3(2,2,2))
	check(not auto_world.can_insert_instance(transform_at(12),protected) and auto_world.insert_instance(transform_at(12),protected)==0,"native placement rejects player intersection atomically")
	check(auto_world.insert_instance(PackedFloat32Array([1]))==0 and auto_world.get_ids().size()==2,"invalid automatic insertion preserves data")
	var saved_auto: PackedByteArray = auto_world.capture_snapshot()
	auto_world.insert_instance(transform_at(16))
	auto_world.restore_snapshot(saved_auto)
	check(auto_world.insert_instance(transform_at(20))==3,"automatic IDs derive from restored authoritative records")
	auto_world.upsert_instances(PackedInt64Array([9223372036854775807]),transform_at(24))
	check(not auto_world.can_insert_instance(transform_at(28)) and auto_world.insert_instance(transform_at(28))==0,"automatic insertion rejects ID overflow without wrapping")
	auto_world.free()
	check_model_exclusion()
	await check_model_history()
	await check_render_streaming()
	var result := {"checks":checks,"failures":failures,"gpu_readback":gpu,"collision_100k":collision_evidence,"render_pages_100k":render_page_evidence}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/static_placements_gpu.json" if gpu else "res://reports/static_placements.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	world.free()
	copy.free()
	print("STATIC_PLACEMENTS_RESULT ",JSON.stringify(result))
	quit(1 if failures else 0)

func check_model_exclusion() -> void:
	var world: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(world)
	var box := BoxMesh.new()
	box.size=Vector3(2,2,2)
	world.configure_asset("tests/exclusion",box)
	world.upsert_instances(PackedInt64Array([1]),transform_at(-32))
	var bounds := AABB(Vector3(-0.25,-0.25,-0.25),Vector3(0.5,0.5,0.5))
	var candidates: Array[Transform3D] = [Transform3D(Basis(),Vector3(-32,0,0)),Transform3D(Basis(),Vector3(0,0,0))]
	check(world.overlap_mask(candidates,bounds)==PackedByteArray([1,0]),"model exclusion uses authored mesh bounds with collision disabled")
	world.upsert_instances(PackedInt64Array([1]),transform_at(0))
	check(world.overlap_mask(candidates,bounds)==PackedByteArray([0,1]),"moving models updates exclusion across signed groups")
	var saved: PackedByteArray = world.capture_snapshot()
	world.remove_instances(PackedInt64Array([1]))
	check(world.overlap_mask(candidates,bounds)==PackedByteArray([0,0]),"removing models reclaims exclusion bounds")
	world.restore_snapshot(saved)
	check(world.overlap_mask(candidates,bounds)==PackedByteArray([0,1]),"model restoration rebuilds authoritative exclusion")
	var mesh: Mesh = load("res://addons/structures/prefabs/doorway_model.tres")
	var parts: Array[AABB] = mesh.get_meta("collision_boxes")
	world.configure_compound_collision(parts,0,8,1,24,3)
	var door_candidates: Array[Transform3D] = [Transform3D(Basis(),Vector3(0,1,0)),Transform3D(Basis(),Vector3(-1.5,1,0))]
	check(world.overlap_mask(door_candidates,bounds)==PackedByteArray([0,1]),"compound exclusion preserves openings even with physics disabled")
	world.configure_compound_collision(parts,16,1,1,3,3)
	world.set_collision_focus(Vector3(1000,0,0))
	check(world.overlap_mask(door_candidates,bounds)==PackedByteArray([0,1]),"distant physics admission does not change model exclusion")
	world.position=Vector3(32,0,0)
	var shifted: Array[Transform3D] = [Transform3D(Basis(),Vector3(30.5,1,0))]
	check(world.overlap_mask(shifted,bounds)==PackedByteArray([1]),"model exclusion respects collection transforms")
	check(world.overlap_mask(shifted,AABB(Vector3.ZERO,Vector3(-1,1,1))).is_empty(),"invalid prototype bounds reject exclusion query")
	var invalid: Array[Transform3D] = [Transform3D(Basis(),Vector3(NAN,0,0))]
	check(world.overlap_mask(invalid,bounds).is_empty(),"nonfinite candidates reject exclusion query")
	var many: Array[Transform3D] = []
	many.resize(65537)
	check(world.overlap_mask(many,bounds).is_empty(),"exclusion query candidate count is bounded")
	var blocks: Node3D = ClassDB.instantiate("NativeBlockWorld")
	root.add_child(blocks)
	blocks.set_cells(PackedInt32Array([0,0,0,1]))
	var query: RefCounted = ClassDB.instantiate("NativeStructureQueries")
	var combined: Array[Transform3D] = [Transform3D(Basis(),Vector3(0.5,0.5,0.5)),shifted[0],Transform3D(Basis(),Vector3(100,0,0))]
	check(query.overlap_mask(blocks,[world],combined,bounds)==PackedByteArray([1,1,0]),"native combined query unions block and model exclusion")
	check(query.overlap_mask(blocks,[42],combined,bounds).is_empty(),"combined query rejects invalid model collections")
	world.free()
	blocks.free()

func check_model_history() -> void:
	var a: Node3D = ClassDB.instantiate("NativeStaticBatch")
	var b: Node3D = ClassDB.instantiate("NativeStaticBatch")
	root.add_child(a)
	root.add_child(b)
	a.configure_asset("tests/history_a",BoxMesh.new())
	b.configure_asset("tests/history_b",BoxMesh.new())
	var empty_a: PackedByteArray = a.capture_snapshot()
	var empty_b: PackedByteArray = b.capture_snapshot()
	var history: RefCounted = ClassDB.instantiate("NativeStaticHistory")
	check(history.configure([a,b],1024*1024,256),"native model journal registers multiple collections")
	var observed := {"steps":-1,"reentrant":true,"signals":0}
	var observer := func():
		observed.steps=history.stats().undo_steps
		observed.reentrant=history.undo()
		observed.signals+=1
	a.changed.connect(observer)
	var aid: int = history.insert(a,transform_at(4))
	check(aid==1 and observed.steps==1 and not observed.reentrant and observed.signals==1,"history cursor is published before one changed signal; reentrant replay rejects")
	a.changed.disconnect(observer)
	var bid: int = history.insert(b,transform_at(8))
	check(bid==1 and history.update(a,aid,transform_at(-40)),"journal edits span collections and signed spatial groups")
	var moved_a: PackedByteArray = a.capture_snapshot()
	check(history.erase(b,bid) and b.get_instance(bid).is_empty(),"journal removal deletes the exact placement")
	check(history.stats().undo_steps==4 and history.stats().redo_steps==0,"chronological journal records four small deltas")
	check(history.undo() and b.get_instance(bid)==transform_at(8),"undo restores removed model with original stable ID")
	check(history.undo() and a.get_instance(aid)==transform_at(4),"next undo crosses collection boundary and restores transform")
	check(history.undo() and b.get_instance(bid).is_empty(),"next undo removes the second catalog placement")
	check(history.undo() and a.capture_snapshot()==empty_a and b.capture_snapshot()==empty_b,"full undo restores exact pre-edit authored snapshots")
	check(not history.undo() and history.stats().redo_steps==4,"empty undo leaves future intact")
	var protect := AABB(Vector3(3,-1,-1),Vector3(2,2,2))
	check(not history.redo(protect) and a.capture_snapshot()==empty_a and history.stats().redo_steps==4,"redo cannot recreate model through protected player bounds")
	check(history.redo() and history.redo() and history.redo() and history.redo(),"redo replays the complete chronological sequence")
	check(a.capture_snapshot()==moved_a and b.capture_snapshot()==empty_b,"redo reproduces exact final state and stable IDs")
	check(not history.update(a,aid,PackedFloat32Array([1])) and not history.erase(a,999),"invalid history edits reject without mutation")
	check(not history.configure([a,a],1000,10) and not history.configure([42],1000,10) and not history.configure([a],-1,10),"invalid journal configuration preserves existing registry and history")
	check(history.stats().undo_steps==4 and history.stats().collections==2,"rejected edits and configuration preserve history")
	check(history.undo(),"undo removal prepares a protected restore test")
	check(history.erase(b,bid),"remove restored model as a new branch")
	var protect_b := AABB(Vector3(7,-1,-1),Vector3(2,2,2))
	check(not history.undo(protect_b) and b.get_instance(bid).is_empty() and history.stats().undo_steps==4,"undo deletion also protects player and retains retryable command")
	check(history.undo() and history.redo(protect_b),"after moving clear undo works; redo deletion may remove an overlapping object")
	check(history.undo() and history.update(a,aid,transform_at(-40)) and history.stats().redo_steps==1,"no-op update retains redo branch")
	check(history.insert(a,transform_at(20))>0 and history.stats().redo_steps==0,"new edit discards obsolete redo branch")
	var prior_steps: int = history.stats().undo_steps
	check(not a.upsert_instances(PackedInt64Array([1]),PackedFloat32Array([0])) and history.stats().undo_steps==prior_steps,"rejected external mutation does not invalidate journal")
	a.upsert_instances(PackedInt64Array([1]),transform_at(100))
	check(not history.undo() and history.stats().undo_steps==0 and history.stats().redo_steps==0,"external authored mutation forms a history barrier across all collections")
	check(a.get_instance(1)==transform_at(100),"stale undo never overwrites external data")
	history.insert(a,transform_at(104))
	var checkpoint: PackedByteArray = a.capture_snapshot()
	a.restore_snapshot(checkpoint)
	check(not history.undo() and a.capture_snapshot()==checkpoint,"even identical snapshot restoration invalidates old model commands")
	history.insert(a,transform_at(108))
	a.configure_asset("tests/history_a",BoxMesh.new())
	check(history.stats().undo_steps==0,"changing the collection mesh invalidates history")
	history.insert(a,transform_at(112))
	a.set_instances(BoxMesh.new(),transform_at(0))
	check(not history.undo(),"bulk collection replacement is a history barrier")
	a.restore_snapshot(empty_a)
	b.restore_snapshot(empty_b)
	var record_size: int = history.stats().record_size
	check(history.configure([a,b],record_size*2,100),"record budget can be smaller than step budget")
	for x in [4,8,12]:
		history.insert(a,transform_at(x))
	check(history.stats().undo_steps==2 and history.stats().record_bytes==record_size*2,"byte budget drops oldest delta without snapshot-sized allocations")
	check(history.undo() and history.undo() and not history.undo() and a.get_ids()==PackedInt64Array([1]),"trimmed history cannot undo past retained boundary")
	check(history.stats().record_bytes==record_size*2 and history.redo() and history.redo(),"undo and redo share one record budget")
	check(history.configure([a,b],1024*1024,1),"step cap can be configured independently")
	history.insert(a,transform_at(16))
	history.insert(b,transform_at(20))
	check(history.stats().undo_steps==1 and history.undo() and a.get_ids().size()==4,"step cap keeps newest edit across asset types")
	check(history.configure([a,b],record_size-1,256) and history.insert(b,transform_at(24))>0,"undersized history budget permits authored edits")
	check(history.stats().undo_steps==0 and history.stats().record_bytes==0 and history.stats().unrecorded_edits>0,"unrecordable edit retains no stale history")
	history.configure([a,b],1024*1024,256)
	a.upsert_instances(PackedInt64Array([9000000001]),transform_at(28))
	check(history.erase(a,9000000001) and history.undo() and a.get_instance(9000000001)==transform_at(28),"undo preserves stable IDs beyond 32-bit range")
	# Compound openings are usable player space; protection tests individual parts.
	var door: Mesh = load("res://addons/structures/prefabs/doorway_model.tres")
	var parts: Array[AABB] = door.get_meta("collision_boxes")
	b.restore_snapshot(empty_b)
	b.configure_compound_collision(parts,32,16,4,48,12)
	b.position=Vector3(32,0,0)
	var opening := AABB(Vector3(31.75,0.5,-0.25),Vector3(0.5,1,0.5))
	var post := AABB(Vector3(30.25,0.5,-0.25),Vector3(0.5,1,0.5))
	var door_id: int = history.insert(b,transform_at(0),opening)
	check(door_id>0 and history.erase(b,door_id),"native protection preserves compound opening in transformed collection")
	check(not history.undo(post) and history.undo(opening),"undo uses current collection frame and individual collision parts")
	await settle_collision(b)
	check(not collision_ray(Vector3(30.5,1,-2),Vector3(30.5,1,2)).is_empty(),"undo restoration republishes physical model parts")
	check(history.update(b,door_id,transform_at(8)),"journal update moves compound model")
	await settle_collision(b)
	check(collision_ray(Vector3(30.5,1,-2),Vector3(30.5,1,2)).is_empty(),"history move releases former collision")
	check(history.undo(),"undo model move accepted")
	await settle_collision(b)
	check(not collision_ray(Vector3(30.5,1,-2),Vector3(30.5,1,2)).is_empty(),"undo model move restores collision at original position")
	var samples: Array[Transform3D] = [Transform3D(Basis(),Vector3(30.5,1,0))]
	check(b.overlap_mask(samples,AABB(Vector3(-0.1,-0.1,-0.1),Vector3(0.2,0.2,0.2)))==PackedByteArray([1]),"history restores authoritative vegetation exclusion bounds")
	# Observers can edit or destroy collections; never keep dangling raw pointers.
	var callback := func(): a.upsert_instances(PackedInt64Array([777]),transform_at(200))
	b.changed.connect(callback,CONNECT_ONE_SHOT)
	check(history.insert(b,transform_at(16))>0 and history.stats().undo_steps==0,"external mutation during notification invalidates completed history safely")
	var free_callback := func(): b.free()
	a.changed.connect(free_callback,CONNECT_ONE_SHOT)
	check(history.insert(a,transform_at(204))>0 and history.stats().collections==1 and history.stats().undo_steps==0,"notification may destroy another collection without leaving dangling history")
	history.insert(a,transform_at(208))
	var asset_notice := {"replayed":true}
	var asset_callback := func(): asset_notice.replayed=history.undo()
	a.exclusion_changed.connect(asset_callback,CONNECT_ONE_SHOT)
	a.configure_asset("tests/history_a",BoxMesh.new())
	check(not asset_notice.replayed and history.stats().undo_steps==0,"asset mutation invalidates history before exclusion notification callbacks")
	history.insert(a,transform_at(212))
	a.free()
	check(not history.undo() and history.stats().collections==0 and history.stats().record_bytes==0,"destroyed collection releases journal references and all retained deltas")
