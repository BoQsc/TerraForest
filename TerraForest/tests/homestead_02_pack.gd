# SPDX-License-Identifier: 0BSD
extends SceneTree
const Pack = preload("res://addons/structures/packs/homestead_02/catalog.gd")
const World = preload("res://addons/structures/structures_world.gd")
const Items = preload("res://addons/player_runtime/item_catalog.gd")
const Author = preload("res://addons/structures/packs/homestead_02/author.gd")
var failures := 0
var checks := 0
var folder := ""

func records_at(point: Vector3) -> PackedFloat32Array:
	return PackedFloat32Array([1,0,0,point.x,0,1,0,point.y,0,0,1,point.z])

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="): folder = argument.trim_prefix("--check-evidence-dir=")
	run.call_deferred()

func run() -> void:
	var arguments := OS.get_cmdline_user_args()
	if "--preview-only" in arguments:
		if "--author-picture" in arguments:
			var author := Author.new()
			check(ResourceSaver.save(author.build("picture"),Pack.ROOT+"models/picture.tres") == OK,"rebaked original landscape")
		var entries: Array[Dictionary] = []
		for definition: Dictionary in Pack.definitions():
			entries.append({"mesh":load(Pack.ROOT+"models/"+definition.id+".tres"),"title":Pack.title(definition)})
		await render_pack(entries)
		print("HOMESTEAD02_PREVIEW failures=",failures)
		quit(1 if failures else 0); return
	if "--author-pack" in arguments:
		var author := Author.new()
		DirAccess.make_dir_recursive_absolute(Pack.ROOT + "models")
		for definition: Dictionary in Pack.definitions():
			var mesh := author.build(definition.id)
			check(ResourceSaver.save(mesh,Pack.ROOT+"models/"+definition.id+".tres") == OK,"baked "+definition.id)
		print("HOMESTEAD02_PACK checks=",checks," failures=",failures); quit(1 if failures else 0); return
	var world := World.new(); root.add_child(world)
	var entries := Pack.register(world)
	check(entries.size() == 10,"ten separate native model collections admitted")
	if entries.size() != 10: world.free(); quit(1); return
	var inventory := Items.create_inventory()
	var history: RefCounted = ClassDB.instantiate("NativeStaticHistory")
	check(history.configure(world.model_collections().values(),1048576,256),"shared history owns all pack objects")
	var coordinator := preload("res://addons/player_runtime/construction_inventory.gd").new(); coordinator.gameplay = true
	var recipes := preload("res://addons/structures/construction_catalog.gd").recipes()
	var salvage := preload("res://addons/structures/construction_catalog.gd").salvage_recipes()
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var definition: Dictionary = Pack.definitions()[index]
		var mesh: Mesh = entry.mesh
		check(mesh.get_aabb().size.length() > 0.1 and mesh.get_aabb().position.y >= -0.001,"authored dimensions and bottom anchor: "+definition.id)
		check(mesh.get_meta("pack_id") == Pack.ID and mesh.get_meta("collision_boxes").size() > 0,"pack provenance and collision: "+definition.id)
		check(Items.item_name(entry.item) == definition.name and Items.Objects.TITLES[entry.item] == entry.title and Items.matches(entry.item,"homestead object"),"inventory and placement identity agree: "+definition.id)
		check(recipes[entry.id] == entry.costs and (salvage.has(entry.id) == not definition.salvage.is_empty()),"construction and salvage share the manifest: "+definition.id)
		var profile := preload("res://addons/player_runtime/durability_catalog.gd").model_profile(entry.id)
		check(profile.name == definition.name and profile.health == int(definition.health),"shared damage profile: "+definition.id)
		check(inventory.grant(entry.item,1,inventory.snapshot().revision).ok,"carried object registered: "+definition.id)
		var pose := Transform3D(Basis.IDENTITY,Vector3(index*4,0,0))
		var records := records_at(pose.origin)
		var id: int = coordinator.place_model(history,entry.collection,inventory,records,AABB(),PackedInt64Array([entry.item,1]))
		check(id > 0,"paid carried placement: "+definition.id)
		var before: PackedByteArray = inventory.capture_storage_snapshot()
		check(coordinator.place_model(history,entry.collection,inventory,records,AABB(),PackedInt64Array([entry.item,1])) == 0 and inventory.capture_storage_snapshot() == before,"no unpaid duplicate: "+definition.id)
	var snapshot: PackedByteArray = world.capture_storage_snapshot()
	check(not snapshot.is_empty(),"combined structure snapshot includes pack identities")
	var reopened := World.new(); root.add_child(reopened); Pack.register(reopened)
	check(reopened.restore_storage_snapshot(snapshot) and reopened.capture_storage_snapshot() == snapshot,"fresh native owners reopen every placement byte-exactly")
	# A pre-pack world has no sections for these models. Restore must leave them empty.
	var legacy := World.new(); root.add_child(legacy)
	legacy.register_model("furniture/table/v1",BoxMesh.new())
	var legacy_bytes: PackedByteArray = legacy.capture_storage_snapshot()
	var upgraded := World.new(); root.add_child(upgraded)
	upgraded.register_model("furniture/table/v1",BoxMesh.new()); Pack.register(upgraded)
	check(upgraded.restore_storage_snapshot(legacy_bytes),"pre-pack structure snapshot opens with new catalog")
	var empty := true
	for entry: Dictionary in entries: empty = empty and upgraded.model(entry.id).get_ids().is_empty()
	check(empty,"older saves gain no unsolicited furniture")
	# A bounded mixed-density fixture, not a graphical FPS qualification.
	var dense_world := World.new(); root.add_child(dense_world)
	var dense := Pack.register(dense_world)
	if not dense.is_empty():
		var start := Time.get_ticks_usec()
		var count := 0
		for index in 1000:
			var entry: Dictionary = dense[index % dense.size()]
			var pose := Transform3D(Basis.IDENTITY,Vector3((index%25)*3,0,(index/25)*3))
			if entry.collection.insert_instance(records_at(pose.origin),AABB()) > 0: count += 1
		check(count == 1000,"1000 mixed pack placements use ten native collections")
		print("HOMESTEAD02_DENSITY records=",count," author_us=",Time.get_ticks_usec()-start," snapshot_bytes=",dense_world.capture_storage_snapshot().size())
	dense_world.free()
	var lights := Pack.light_sources(world)
	check(lights.size()==1 and lights[0].collection==world.model(Pack.key("lamp")),"table lamp uses the existing resident light source contract")
	var light_pool: Node3D=ClassDB.instantiate("NativeResidentLights"); world.add_child(light_pool)
	check(light_pool.configure(lights,4),"native light pool admits the pack lamp")
	await wall_checks(world,entries)
	if "--bake-icons" in arguments:
		check(DisplayServer.get_name() != "headless","icon authoring has a renderer")
		if DisplayServer.get_name() != "headless": await render_pack(entries)
	else:
		for entry: Dictionary in entries: check(Pack.icon(entry.item) != null,"pack icon: "+str(entry.item))
	check(load("res://demo/world.gd") != null,"game world compiles with the pack")
	world.free(); reopened.free(); legacy.free(); upgraded.free()
	await process_frame
	print("HOMESTEAD02_PACK checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func wall_checks(world: Node3D, entries: Array[Dictionary]) -> void:
	var mount=preload("res://addons/structures/wall_object_placement.gd")
	var body := StaticBody3D.new(); body.collision_layer=2
	var shape := BoxShape3D.new(); shape.size=Vector3(8,5,0.2)
	var collider := CollisionShape3D.new(); collider.shape=shape; body.add_child(collider); root.add_child(body)
	for side in 4:
		var basis := Basis(Vector3.UP,side*PI*0.5)
		var normal := basis*Vector3.FORWARD
		body.transform=Transform3D(basis,-normal*2.1+Vector3.UP*2.5)
		await physics_frame; await physics_frame
		for entry: Dictionary in entries:
			if entry.get("mount") != "wall": continue
			var hit := {"position":-normal*2.0+Vector3.UP*2.17+basis.x*0.13,"normal":normal}
			var result: Dictionary=mount.target(entry,hit,0.1)
			check(result.placement_ok and (-result.transform.basis.z).is_equal_approx(normal),"wall mount faces out on side %d: %s" % [side,entry.title])
			check(mount.supported(world.blocks,entry,result.transform,[]),"authored wall supports hit the real collider: %s"%entry.title)
			check(not mount.target(entry,{"position":Vector3.ZERO,"normal":Vector3.UP}).placement_ok,"wall object rejects floor mounting")
	body.free(); await physics_frame; await physics_frame
	for entry: Dictionary in entries:
		if entry.get("mount") != "wall": continue
		var result: Dictionary=mount.target(entry,{"position":Vector3(0,2.17,2),"normal":Vector3.FORWARD})
		check(not mount.supported(world.blocks,entry,result.transform,[]),"missing wall cannot support a floating decoration")

func lighting(parent: Node3D) -> void:
	var environment := WorldEnvironment.new(); var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR; settings.background_color = Color("192a2c")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; settings.ambient_light_color = Color("c6d9dd"); settings.ambient_light_energy = 0.7
	environment.environment = settings; parent.add_child(environment)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-48,-35,0); sun.light_energy = 1.8; sun.shadow_enabled = true; parent.add_child(sun)
	var fill := DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-25,140,0); fill.light_energy = 0.6; parent.add_child(fill)

func render_pack(entries: Array[Dictionary]) -> void:
	var atlas := Image.create(1280,512,false,Image.FORMAT_RGBA8); atlas.fill(Color.TRANSPARENT)
	var layout := Control.new(); layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(layout)
	var background := ColorRect.new(); background.color = Color("101e20"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); layout.add_child(background)
	var heading := Label.new(); heading.text = "HOMESTEAD 02   /   LIVED-IN DETAILS"; heading.position = Vector2(55,30); heading.add_theme_font_size_override("font_size",34); layout.add_child(heading)
	var subheading := Label.new(); subheading.text = "10 original objects  ·  Woven linen / faded teal / amber glass"; subheading.position=Vector2(57,78); subheading.add_theme_font_size_override("font_size",20); layout.add_child(subheading)
	for index in entries.size():
		var view := SubViewport.new(); view.size = Vector2i(512,512); view.own_world_3d = true; view.transparent_bg = true; view.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(view)
		var stage := Node3D.new(); view.add_child(stage); lighting(stage)
		var instance := MeshInstance3D.new(); instance.mesh = entries[index].mesh; stage.add_child(instance)
		var bounds := instance.mesh.get_aabb(); var extent := maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))
		var camera := Camera3D.new(); camera.projection = Camera3D.PROJECTION_ORTHOGONAL; camera.size = extent*1.55
		camera.position = bounds.get_center()+Vector3(1.6,1.10,-2.3)*extent; stage.add_child(camera); camera.look_at(bounds.get_center()); camera.make_current()
		for frame in 4: await process_frame
		await RenderingServer.frame_post_draw
		var pixels := view.get_texture().get_image(); pixels.resize(256,256,Image.INTERPOLATE_LANCZOS)
		atlas.blit_rect(pixels,Rect2i(0,0,256,256),Vector2i((index%5)*256,(index/5)*256))
		var tile := TextureRect.new(); tile.texture = ImageTexture.create_from_image(pixels); tile.position = Vector2(45+(index%5)*370,140+(index/5)*440); tile.size = Vector2(330,330); tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; layout.add_child(tile)
		var label := Label.new(); label.text = entries[index].title.trim_prefix(Pack.TITLE+" · "); label.position = tile.position+Vector2(0,330); label.size.x = 330; label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; label.add_theme_font_size_override("font_size",23); layout.add_child(label)
		var dimensions := Label.new(); dimensions.text = "%.2f × %.2f × %.2f m" % [bounds.size.x,bounds.size.y,bounds.size.z]; dimensions.position=tile.position+Vector2(0,362); dimensions.size.x=330; dimensions.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER; dimensions.modulate=Color("9baead"); layout.add_child(dimensions)
		view.free()
	check(atlas.save_png(Pack.ROOT+"icons.trtex") == OK,"authored pack-owned icon atlas")
	await process_frame; await RenderingServer.frame_post_draw
	if not folder.is_empty(): check(root.get_texture().get_image().save_png(folder.path_join("homestead_02.png")) == OK,"retained labelled contact sheet")
	layout.free()
