# SPDX-License-Identifier: 0BSD
extends SceneTree
const Author = preload("res://addons/structures/grand_buildings/author.gd")
const Catalog = preload("res://addons/structures/grand_buildings/catalog.gd")
const Packs = preload("res://addons/structures/pack_registry.gd")
var checks := 0
var failures := 0
var folder := ""
var world: Node3D
var camera: Camera3D
var stage: Node3D
var report := {"buildings":[]}
var restore_folder := ""
var only_building := ""
var snapshot: PackedByteArray

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="): folder=arg.trim_prefix("--check-evidence-dir=")
		if arg.begins_with("--restore-from="): restore_folder=arg.trim_prefix("--restore-from=")
		if arg.begins_with("--building="): only_building=arg.trim_prefix("--building=")
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
	return ok

func setup() -> Node3D:
	var out := preload("res://addons/structures/structures_world.gd").new(); root.add_child(out)
	Packs.register(out)
	preload("res://addons/structures/window_catalog.gd").register(out)
	var objects := preload("res://addons/structures/object_catalog.gd").new(); objects.prepare(); objects.register_all(out)
	return out

func floor_measure(asset: Resource) -> int:
	# Independent measurement of supported two-metre-clear cell columns.
	var occupied := {}; var levels := {}; var records: PackedInt32Array=asset.get_records()
	if asset.has_meta("floor_areas"):
		for row: Dictionary in asset.get_meta("floor_areas"): levels[int(row.level)-1]=true
	else: levels={0:true,4:true}
	for i in range(0,records.size(),4): occupied[Vector3i(records[i],records[i+1],records[i+2])]=records[i+3]
	var count := 0
	for point: Vector3i in occupied:
		if not levels.has(point.y): continue
		var shape: int=world.blocks.decode_block(occupied[point]).shape
		if shape in [1,8] and not occupied.has(point+Vector3i.UP) and not occupied.has(point+Vector3i.UP*2): count+=1
	return count

func run() -> void:
	world=setup()
	if "--author-buildings" in OS.get_cmdline_user_args():
		for index in Catalog.IDS.size():
			if not only_building.is_empty() and Catalog.IDS[index]!=only_building: continue
			var authored: Resource=Author.new().build(world.blocks,index)
			if check(authored!=null,"author "+Catalog.IDS[index]):
				check(ResourceSaver.save(authored,"res://addons/structures/grand_buildings/"+Catalog.IDS[index]+".tres")==OK,"bake "+Catalog.IDS[index])
		if "--bake-only" in OS.get_cmdline_user_args(): finish(); return
	if not restore_folder.is_empty():
		var original: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(restore_folder.path_join("grand_buildings.json")))
		for row: Dictionary in original.buildings:
			var path := restore_folder.path_join(row.id+".bin")
			var bytes := FileAccess.get_file_as_bytes(path)
			check(FileAccess.get_sha256(path)==row.snapshot_sha256,"fresh-process fixture hash "+row.id)
			check(world.restore_storage_snapshot(bytes) and world.capture_storage_snapshot()==bytes,"fresh-process exact fabric, doors and furniture "+row.id)
		finish(); return
	var manor: Resource=preload("res://addons/structures/mansion/catalog.gd").asset()
	var baseline := floor_measure(manor)
	if DisplayServer.get_name()!="headless": lighting()
	for index in Catalog.IDS.size():
		if not only_building.is_empty() and Catalog.IDS[index]!=only_building: continue
		var asset: Resource=Catalog.asset(index)
		if not check(asset!=null,"public catalog loads "+Catalog.IDS[index]): continue
		var area := floor_measure(asset)
		check(area>=baseline*2,"at least twice mansion clear floor area: %d / %d m2"%[area,baseline])
		if index==1:
			var size: Vector3=asset.get_bounds().size; var base: Vector3=manor.get_bounds().size
			check(size.x>=base.x*2 and size.y>=base.y*2 and size.z>=base.z*2,"cathedral doubles full mansion envelope in every axis: "+str(size)+" / "+str(base))
			check(asset.get_meta("basement_interior_m2",0)>=2000,"large two-level basement")
		else: check(asset.get_meta("flats",[]).size()>=50,"at least fifty individually furnished flats")
		check(asset.get_model_attachments().size()<4096 and asset.get_cell_count()<262144,"native prefab budgets retained")
		# Restore an empty compound owner so prior furnishing batches cannot leak.
		world.free(); world=setup()
		var transaction: RefCounted=ClassDB.instantiate("NativePrefabPlacement")
		var placed: Dictionary=transaction.place(world.blocks,asset,Vector3i.ZERO,0,world.model_collections(),[])
		if not check(placed.get("ok",false),"strict compound placement "+Catalog.IDS[index]+": "+str(placed.get("reason",""))):
			diagnose(asset); continue
		world.blocks.set_collision_radius(160); world.blocks.set_focus(asset.get_bounds().get_center()); world.blocks.flush_bakes()
		world.set_model_focus(asset.get_bounds().get_center())
		snapshot=world.capture_storage_snapshot()
		if not check(snapshot.size()<=1024*1024,"snapshot bounded to one MiB"): continue
		var path := folder.path_join(Catalog.IDS[index]+".bin")
		var file := FileAccess.open(path,FileAccess.WRITE); file.store_buffer(snapshot); file.close()
		var reopened := setup()
		check(reopened.restore_storage_snapshot(snapshot) and reopened.capture_storage_snapshot()==snapshot,"exact independent-owner restore "+Catalog.IDS[index]); reopened.free()
		var cells: PackedInt32Array=asset.get_records()
		check(world.blocks.set_cells(PackedInt32Array([cells[0],cells[1],cells[2],0])) and world.blocks.stats().cells==asset.get_cell_count()-1,"individual block removal "+Catalog.IDS[index])
		check(world.restore_storage_snapshot(snapshot),"restore damaged fabric "+Catalog.IDS[index])
		await headroom(asset)
		if "--no-walk" not in OS.get_cmdline_user_args(): await walk(asset)
		report.buildings.append({"id":Catalog.IDS[index],"cells":asset.get_cell_count(),"objects":asset.get_model_attachments().size(),"clear_floor_m2":area,"mansion_clear_floor_m2":baseline,"bounds":str(asset.get_bounds()),"flats":asset.get_meta("flats",[]).size(),"snapshot_sha256":FileAccess.get_sha256(path)})
		if camera!=null: await pictures(asset,index)
	if stage!=null: stage.free()
	var result := FileAccess.open(folder.path_join("grand_buildings.json"),FileAccess.WRITE)
	result.store_string(JSON.stringify(report,"  ")); result.close()
	finish()

func headroom(asset: Resource) -> void:
	for tick in 10: await physics_frame
	var clear := true
	for route: Dictionary in asset.get_meta("stair_routes"):
		if route.kind!="stairs": continue
		for point: Vector3 in [route.start,route.end]:
			var hit: Dictionary=world.blocks.raycast_scene(point+Vector3.UP*.1,point+Vector3.UP*1.81,1,[])
			if not hit.is_empty(): clear=false; print("BLOCKED_HEADROOM ",point," hit=",hit.position)
	check(clear,"standing headroom at every stair landing")

func walk(asset: Resource) -> void:
	var selected := {}
	for route: Dictionary in asset.get_meta("stair_routes"):
		if route.kind!="stairs": continue
		var key := Vector2(route.start.x,route.start.z)
		if not selected.has(key): selected[key]=[route,route]
		if route.start.y<selected[key][0].start.y: selected[key][0]=route
		if route.start.y>selected[key][1].start.y: selected[key][1]=route
	var player := CharacterBody3D.new(); player.collision_mask=15; player.collision_layer=2; player.floor_snap_length=.35; player.floor_max_angle=deg_to_rad(48); player.floor_constant_speed=true; player.safe_margin=.004
	var shape := CollisionShape3D.new(); var capsule := CapsuleShape3D.new(); capsule.radius=.34; capsule.height=1.8; shape.shape=capsule; shape.position.y=.9; player.add_child(shape); root.add_child(player)
	var motor: RefCounted=ClassDB.instantiate("NativePlayerMovement")
	for key: Vector2 in selected:
		for route: Dictionary in selected[key]:
			world.blocks.set_focus(route.start); world.blocks.flush_bakes()
			for reverse in [false,true]:
				var start: Vector3=route.end if reverse else route.start; var end: Vector3=route.start if reverse else route.end
				player.position=start; player.velocity=Vector3.ZERO
				for frame in 8: await physics_frame
				var direction := Vector3(end.x-start.x,0,end.z-start.z).normalized()
				for tick in 240:
					await physics_frame
					player.velocity=motor.walking_velocity(direction,player.velocity,1.0/60,false,player.is_on_floor(),false); motor.move_grounded(player,1.0/60)
					if Vector2(player.position.x-end.x,player.position.z-end.z).length()<.15: break
				for tick in 12:
					await physics_frame; player.velocity=motor.walking_velocity(Vector3.ZERO,player.velocity,1.0/60,false,player.is_on_floor(),false); motor.move_grounded(player,1.0/60)
				check(Vector2(player.position.x-end.x,player.position.z-end.z).length()<.22 and absf(player.position.y-end.y)<.2,"stair "+str(key)+(" down " if reverse else " up ")+str(start.y)+" endpoint="+str(player.position))
	player.free()

func diagnose(asset: Resource) -> void:
	# Bounded collision diagnostics; full cell/geometry dumps are never logged.
	var occupied := {}; var records: PackedInt32Array=asset.get_records(); var count := 0
	for i in range(0,records.size(),4): occupied[Vector3i(records[i],records[i+1],records[i+2])]=true
	for attachment: Dictionary in asset.get_model_attachments():
		var parts: Array=[]
		if Packs.objects.has(attachment.model):
			var row: Dictionary=Packs.objects[attachment.model]; var mesh: Mesh=load(row.directory+"/models/"+row.id+".tres"); parts=mesh.get_meta("collision_boxes")
		elif attachment.model.contains("window"): parts=[AABB(Vector3(-1,0,-.1),Vector3(2,2,.2))]
		else: parts=[AABB(Vector3(0,0,-.07),Vector3(1,2.2,.14))]
		for local: AABB in parts:
			var box: AABB=(attachment.transform*local).grow(-.001)
			for x in range(floori(box.position.x),ceili(box.end.x)):
				for y in range(floori(box.position.y),ceili(box.end.y)):
					for z in range(floori(box.position.z),ceili(box.end.z)):
						if occupied.has(Vector3i(x,y,z)) and count<12:
							print("FURNITURE_BLOCK ",attachment.model," @",attachment.transform.origin," cell=",Vector3i(x,y,z)); count+=1

func lighting() -> void:
	root.mode=Window.MODE_WINDOWED; root.size=Vector2i(1280,720); root.content_scale_size=Vector2i(1280,720)
	stage=Node3D.new(); root.add_child(stage)
	var environment := WorldEnvironment.new(); var settings := Environment.new()
	settings.background_mode=Environment.BG_COLOR; settings.background_color=Color("aab9bb"); settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color=Color("d5e2e0"); settings.ambient_light_energy=.85; settings.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.environment=settings; stage.add_child(environment)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees=Vector3(-48,-35,0); sun.light_energy=1.8; sun.shadow_enabled=true; stage.add_child(sun)
	var ground := MeshInstance3D.new(); ground.name="Ground"
	var plane := PlaneMesh.new(); plane.size=Vector2(400,400)
	var material := StandardMaterial3D.new(); material.albedo_color=Color("6d7c61"); plane.material=material
	ground.mesh=plane; ground.position=Vector3(52,-.01,40); stage.add_child(ground)
	camera=Camera3D.new(); camera.fov=65; camera.near=.05; camera.far=600; stage.add_child(camera); camera.make_current()

func picture(name: String, point: Vector3, look: Vector3, caption: String) -> void:
	camera.position=point; camera.look_at(look); world.set_model_focus(look); world.blocks.set_focus(look); world.blocks.flush_bakes()
	var canvas := CanvasLayer.new(); root.add_child(canvas)
	var label := Label.new(); label.text=caption; label.position=Vector2(30,24); label.add_theme_font_size_override("font_size",24); label.add_theme_color_override("font_shadow_color",Color.BLACK); label.add_theme_constant_override("shadow_offset_x",2); label.add_theme_constant_override("shadow_offset_y",2); canvas.add_child(label)
	for frame in 35: await process_frame
	await RenderingServer.frame_post_draw
	var pixels := root.get_texture().get_image(); pixels.convert(Image.FORMAT_RGB8)
	# Some desktop drivers retain the requested launch viewport after a resize.
	# Normalize the retained review image before allocating encoded output.
	if pixels.get_width()>1280 or pixels.get_height()>720: pixels.resize(1280,720,Image.INTERPOLATE_LANCZOS)
	if not check(pixels.get_width()<=1280 and pixels.get_height()<=720,"capture dimensions fit admission"): canvas.free(); return
	check(pixels.save_png(folder.path_join(name+".png"))==OK,"capture "+name); canvas.free()

func pictures(asset: Resource,index: int) -> void:
	stage.get_node("Ground").position.y=float(asset.get_meta("site_surface_offset",1))-1.01
	var id: String=Catalog.IDS[index]
	var views := [[Vector3(105,53,103),Vector3(30,7,21)],[Vector3(160,85,150),Vector3(51,21,39)],[Vector3(94,58,100),Vector3(27,17,24)]]
	await picture(id+"_exterior",views[index][0],views[index][1],Catalog.TITLES[index]+" / R1 / EDITABLE BUILDING FABRIC")
	if index==1:
		await picture(id+"_interior",Vector3(52,11,75),Vector3(52,22,17),"NAVE / TWO GALLERIES / CLEAR PROCESSION AISLE")
		await picture(id+"_basement",Vector3(52,3.7,71),Vector3(52,2.5,23),"LOWER CRYPT / ARCHIVES / DEEP BASEMENT")
	else:
		var upper := 4.0 if index==2 else 0.0
		await picture(id+"_interior",Vector3(6.5,2.7+upper,18),Vector3(3.8,2+upper,11),"FURNISHED FLAT / LIVING, BEDROOM AND BATHROOM")
		# Roof and upper floors are removed only from this in-memory review section.
		var removed := PackedInt32Array(); var records: PackedInt32Array=asset.get_records()
		for i in range(0,records.size(),4):
			if records[i+1]>=4: removed.append_array(PackedInt32Array([records[i],records[i+1],records[i+2],0]))
		world.blocks.set_cells(removed)
		for batch: Node3D in world.model_collections().values():
			var ids := PackedInt64Array()
			for key in batch.get_ids():
				var transform: PackedFloat32Array=batch.get_instance(key)
				if transform[7]>=4: ids.append(key)
			if not ids.is_empty(): batch.remove_instances(ids)
		await picture(id+"_plan",Vector3(45,68,60),Vector3(30,0,23),"GROUND FLOOR SECTION / INDIVIDUAL ROOMS, CORRIDOR AND STAIR CORE")
		check(world.restore_storage_snapshot(snapshot),"section restores complete original building")

func finish() -> void:
	world.free()
	print("GRAND_BUILDINGS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
