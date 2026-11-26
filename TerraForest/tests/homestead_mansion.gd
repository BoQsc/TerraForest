# SPDX-License-Identifier: 0BSD
extends SceneTree
const Author=preload("res://addons/structures/mansion/author.gd")
const Packs=preload("res://addons/structures/pack_registry.gd")
var checks:=0
var failures:=0
var folder:=""
var world: Node3D
var camera: Camera3D
var stage: Node3D
var asset: Resource
var full_snapshot:=PackedByteArray()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="): folder=arg.trim_prefix("--check-evidence-dir=")
	run.call_deferred()
func setup() -> Node3D:
	var out:=preload("res://addons/structures/structures_world.gd").new(); root.add_child(out)
	Packs.register(out)
	preload("res://addons/structures/window_catalog.gd").register(out)
	var objects:=preload("res://addons/structures/object_catalog.gd").new(); objects.prepare(); objects.register_all(out)
	return out
func run() -> void:
	world=setup()
	if "--author-mansion" in OS.get_cmdline_user_args():
		asset=Author.new().build(world.blocks)
		check(asset!=null,"authored mansion cells and attachments")
		if asset!=null: check(ResourceSaver.save(asset,Author.PATH)==OK,"baked separate mansion prefab")
		if "--check-layout" not in OS.get_cmdline_user_args():
			world.free(); print("HOMESTEAD_MANSION checks=",checks," failures=",failures); quit(1 if failures else 0); return
	asset=load(Author.PATH)
	check(asset!=null,"mansion asset loads")
	if asset==null: world.free(); quit(1); return
	var required: PackedInt32Array=asset.get_meta("homestead_items")
	var all_present:=true
	for item in range(720,820): all_present=all_present and item in required
	check(all_present,"every one of the 100 Homestead objects has a room placement")
	check(asset.get_meta("room_labels").size()>=12,"distinct purpose-built rooms")
	var transaction: RefCounted=ClassDB.instantiate("NativePrefabPlacement")
	var started:=Time.get_ticks_usec()
	var placed: Dictionary=transaction.place(world.blocks,asset,Vector3i.ZERO,0,world.model_collections(),[])
	check(placed.get("ok",false),"combined native placement: "+str(placed.get("reason","")))
	print("MANSION_LAYOUT cells=",asset.get_cell_count()," objects=",asset.get_model_attachments().size()," placement_us=",Time.get_ticks_usec()-started)
	if not placed.get("ok",false): diagnose(); world.free(); quit(1); return
	world.blocks.set_focus(Vector3(19,4,16)); world.blocks.set_collision_radius(80); world.blocks.flush_bakes(); world.set_model_focus(Vector3(19,4,16))
	full_snapshot=world.capture_storage_snapshot()
	var reopened:=setup()
	check(reopened.restore_storage_snapshot(full_snapshot) and reopened.capture_storage_snapshot()==full_snapshot,"fresh native owners restore exact mansion and furnishings")
	reopened.free()
	var cells: PackedInt32Array=asset.get_records()
	check(world.blocks.set_cells(PackedInt32Array([cells[0],cells[1],cells[2],0])) and world.blocks.stats().cells==asset.get_cell_count()-1,"single masonry block remains independently removable")
	check(world.restore_storage_snapshot(full_snapshot),"restore original after removal")
	# Native spatial inspection is independent of collision proxy residency.
	var queries: RefCounted=ClassDB.instantiate("NativeStructureQueries")
	var nearby: Dictionary=queries.nearby_models(world.model_collections().values(),Vector3(34,2,26),24,128)
	check(not nearby.objects.is_empty() and nearby.objects.size()<=128 and nearby.scanned<=8192,"bounded native inspection query finds furnishings")
	var sorted:=true; var previous:=-1.0
	for row: Dictionary in nearby.objects:
		sorted=sorted and row.distance>=previous; previous=row.distance
	check(sorted,"inspection candidates prioritize nearest objects")
	await supported_details()
	if "--pictures-only" not in OS.get_cmdline_user_args(): await walk_stairs()
	if DisplayServer.get_name()!="headless":
		lighting()
		await picture("mansion_exterior",Vector3(48,24,49),Vector3(19,4,15),"HOMESTEAD MANOR / COURTYARD MANSION R2")
		# A faithful reversible section exposes the ground-floor room layout.
		var removed:=PackedInt32Array()
		for i in range(0,cells.size(),4):
			if cells[i+1]>=4: removed.append_array(PackedInt32Array([cells[i],cells[i+1],cells[i+2],0]))
		world.blocks.set_cells(removed)
		for batch: Node3D in world.model_collections().values():
			var upper_ids:=PackedInt64Array()
			for id in batch.get_ids():
				var transform: PackedFloat32Array=batch.get_instance(id)
				if transform[7]>=4: upper_ids.append(id)
			if not upper_ids.is_empty(): batch.remove_instances(upper_ids)
		await picture("mansion_plan",Vector3(40,32,42),Vector3(19,0,15),"GROUND FLOOR / KITCHEN, DINING, STUDY, SALON, UTILITY & WORKSHOP")
		check(world.restore_storage_snapshot(full_snapshot),"cutaway returns to full saved mansion")
		await picture("mansion_salon",Vector3(30.5,2.8,22.8),Vector3(34.5,1.7,27),"GARDEN SALON / HOMESTEAD LIVING ROOM OBJECTS")
		await picture("mansion_dining",Vector3(29.5,2.8,10.7),Vector3(34,1.8,4.5),"DINING ROOM / HOMESTEAD 10")
		await picture("mansion_bedroom",Vector3(8.8,6.8,29),Vector3(3.9,5.8,25),"PRINCIPAL BEDROOM / HOMESTEAD 01 & 09")
		await picture("mansion_workshop",Vector3(8.8,2.8,29),Vector3(3.7,1.7,24),"WORKSHOP / HOMESTEAD 04")
		stage.free()
	world.free(); await process_frame
	print("HOMESTEAD_MANSION checks=",checks," failures=",failures); quit(1 if failures else 0)
func supported_details() -> void:
	for tick in 30: await physics_frame
	for detail: Dictionary in asset.get_meta("furnishing_layout"):
		if detail.item not in [763,745,803,806,808,817]: continue
		var row: Dictionary=Packs.by_item[detail.item]; var mesh: Mesh=load(row.directory+"/models/"+row.id+".tres")
		var bottom:=INF
		for box: AABB in mesh.get_meta("collision_boxes"): bottom=minf(bottom,box.position.y)
		var start: Vector3=detail.position+Vector3.UP*(bottom-.002)
		var support: Dictionary=world.blocks.raycast_scene(start,start-Vector3.UP*.08,7,[])
		check(not support.is_empty() and support.normal.y>.9,"detail rests on its furniture surface: "+row.id)
func walk_stairs() -> void:
	world.blocks.flush_bakes()
	var player:=CharacterBody3D.new(); player.collision_mask=15; player.collision_layer=2; player.floor_snap_length=.35; player.floor_max_angle=deg_to_rad(48); player.floor_constant_speed=true; player.safe_margin=.004
	var shape:=CollisionShape3D.new(); var capsule:=CapsuleShape3D.new(); capsule.radius=.34; capsule.height=1.8; shape.shape=capsule; shape.position.y=.9; player.add_child(shape); root.add_child(player)
	var motor: RefCounted=ClassDB.instantiate("NativePlayerMovement")
	for route: Dictionary in asset.get_meta("stair_routes"):
		for reverse in [false,true]:
			var start: Vector3=route.end if reverse else route.start; var end: Vector3=route.start if reverse else route.end
			player.position=start; player.velocity=Vector3.ZERO
			for frame in 12: await physics_frame
			var direction:=Vector3(end.x-start.x,0,end.z-start.z).normalized()
			for tick in 240:
				await physics_frame
				player.velocity=motor.walking_velocity(direction,player.velocity,1.0/60,false,player.is_on_floor(),false); motor.move_grounded(player,1.0/60)
				if Vector2(player.position.x-end.x,player.position.z-end.z).length()<.15: break
			for tick in 20:
				await physics_frame; player.velocity=motor.walking_velocity(Vector3.ZERO,player.velocity,1.0/60,false,player.is_on_floor(),false); motor.move_grounded(player,1.0/60)
			check(Vector2(player.position.x-end.x,player.position.z-end.z).length()<.20 and absf(player.position.y-end.y)<.2,"walk main stair "+("down" if reverse else "up")+" endpoint="+str(player.position))
	player.free()

func diagnose() -> void:
	var occupied: Dictionary={}; var records: PackedInt32Array=asset.get_records()
	for i in range(0,records.size(),4): occupied[Vector3i(records[i],records[i+1],records[i+2])]=true
	var previous: Array[Dictionary]=[]
	for attachment: Dictionary in asset.get_model_attachments():
		var parts: Array=[]
		if Packs.objects.has(attachment.model):
			var row: Dictionary=Packs.objects[attachment.model]; var mesh: Mesh=load(row.directory+"/models/"+row.id+".tres"); parts=mesh.get_meta("collision_boxes")
		elif attachment.model.contains("window"): parts=[AABB(Vector3(-1,0,-.1),Vector3(2,2,.2))]
		else: parts=[AABB(Vector3(0,0,-.07),Vector3(1,2.2,.14))]
		var clashes:=[]; var boxes: Array[AABB]=[]
		for local: AABB in parts:
			var bounds: AABB=(attachment.transform*local).grow(-.0001); boxes.append(bounds)
			var low:=Vector3i(bounds.position.floor()); var high:=Vector3i(bounds.end.floor())
			for x in range(low.x,high.x+1):
				for y in range(low.y,high.y+1):
					for z in range(low.z,high.z+1):
						if occupied.has(Vector3i(x,y,z)): clashes.append(Vector3i(x,y,z))
			for prior: Dictionary in previous:
				if bounds.intersects(prior.bounds): print("MODEL_OVERLAP ",attachment.model," @",attachment.transform.origin," / ",prior.key," @",prior.point); break
		if not clashes.is_empty(): print("BLOCK_OVERLAP ",attachment.model," @",attachment.transform.origin," cells=",clashes.slice(0,4))
		for box: AABB in boxes: previous.append({"bounds":box,"key":attachment.model,"point":attachment.transform.origin})
func lighting() -> void:
	stage=Node3D.new(); root.add_child(stage)
	var environment:=WorldEnvironment.new(); var settings:=Environment.new(); settings.background_mode=Environment.BG_COLOR; settings.background_color=Color("aab9bb"); settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color=Color("d5e2e0"); settings.ambient_light_energy=.85; settings.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.environment=settings; stage.add_child(environment)
	var sun:=DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-48,-35,0); sun.light_energy=1.8; sun.shadow_enabled=true; stage.add_child(sun)
	var ground:=MeshInstance3D.new(); var plane:=PlaneMesh.new(); plane.size=Vector2(160,160); var material:=StandardMaterial3D.new(); material.albedo_color=Color("6d7c61"); plane.material=material; ground.mesh=plane; ground.position=Vector3(19,-.01,16); stage.add_child(ground)
	camera=Camera3D.new(); camera.fov=68; camera.near=.05; stage.add_child(camera); camera.make_current()
func picture(name: String, point: Vector3, look: Vector3, caption: String) -> void:
	camera.position=point; camera.look_at(look); world.set_model_focus(look); world.blocks.set_focus(look); world.blocks.flush_bakes()
	var canvas:=CanvasLayer.new(); root.add_child(canvas); var label:=Label.new(); label.text=caption; label.position=Vector2(30,24); label.add_theme_font_size_override("font_size",24); label.add_theme_color_override("font_shadow_color",Color.BLACK); label.add_theme_constant_override("shadow_offset_x",2); label.add_theme_constant_override("shadow_offset_y",2); canvas.add_child(label)
	for frame in 35: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(name+".png"))==OK,"capture "+name); canvas.free()
