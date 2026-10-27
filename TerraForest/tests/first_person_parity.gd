extends "res://tests/first_person_protection.gd"

func equip(item:int)->void:
	game.tool_view.equip(item)
	var human:Node=game.tool_view.human
	human.animation_player.play(human.clips[human._motion_clip("Idle")],0)
	human.animation_player.advance(.2)
	human.torch_effects.set_process(false)
	if item==6:human.torch_effects.advance(.4)
	await frames(5)

func compare(label:String)->void:
	game.first_person_view.set_enabled(false,false);var before:=await photo(label+"_off")
	game.first_person_view.set_enabled(true,false);var after:=await photo(label+"_on")
	var delta:=difference(before,after);results[label]=delta
	check(delta.mean_error<.0005 and delta.changed_fraction<.002,label+" preserves lighting, ordinary shadows and silhouette")
	var region:=Rect2i(960,700,640,380)
	var hands:=difference(before.get_region(region),after.get_region(region));results[label+"_hands"]=hands
	check(hands.mean_error<.0005 and hands.changed_fraction<.002,label+" also matches inside the hand/shaft region")
	check(not game.first_person_view.overlay_active and game.first_person_view.viewport.render_target_update_mode==SubViewport.UPDATE_DISABLED,label+" needs no extra camera or detailed shadow pass")

func orange_pixels(picture:Image)->int:
	var count:=0
	for row in range(0,picture.get_height(),2):
		for column in range(picture.get_width()/2,picture.get_width(),2):
			var color:=picture.get_pixel(column,row)
			if color.r>.5 and color.g>.15 and color.b<.4 and color.r>color.g*1.15:count+=1
	return count

func run()->void:
	folder="res://reports/first_person_parity"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--viewmodel-evidence="):folder=argument.trim_prefix("--viewmodel-evidence=")
	folder=ProjectSettings.globalize_path(folder);DirAccess.make_dir_recursive_absolute(folder)
	var environment:=Environment.new();environment.background_mode=Environment.BG_SKY
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color("a6b8cf");environment.ambient_light_energy=.35
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var sky:=Sky.new();sky.radiance_size=Sky.RADIANCE_SIZE_128;sky.sky_material=ProceduralSkyMaterial.new();environment.sky=sky
	environment.fog_enabled=true;environment.fog_density=.00055;environment.fog_light_color=Color("a7c4cd")
	var host:=WorldEnvironment.new();host.environment=environment;root.add_child(host)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-90,0,0);sun.shadow_enabled=true;sun.directional_shadow_max_distance=256
	root.add_child(sun)
	game=Fixture.new();root.add_child(game);game.tool_view.set_process(false);game.tool_view.human.set_process(false)
	await equip(1);await compare("outdoors_pickaxe")
	var assets:=preload("res://addons/vegetation/assets.gd").new()
	if check(assets.build(),"production tree geometry, materials and shadow meshes load"):
		assets.uniforms(game.camera.global_position,Vector3.UP,0,0,448)
		var tree:=Node3D.new();root.add_child(tree)
		for kind in [0,3]:
			var node:=MultiMeshInstance3D.new();node.multimesh=MultiMesh.new();node.multimesh.transform_format=MultiMesh.TRANSFORM_3D
			node.multimesh.use_custom_data=true;node.multimesh.mesh=assets.meshes[kind];node.multimesh.instance_count=1
			node.multimesh.set_instance_transform(0,Transform3D(Basis.IDENTITY,Vector3(2,0,-2)))
			node.multimesh.set_instance_custom_data(0,Color(.25,1,0,0))
			node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind==0 else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			tree.add_child(node)
		await compare("under_tree_pickaxe")
		await equip(6);await compare("under_tree_torch")
		tree.free();await frames()
	var structures:=preload("res://addons/structures/structures_world.gd").new();root.add_child(structures)
	if check(structures.prepare(),"native building renderer prepares"):
		preload("res://addons/structures/furniture_catalog.gd").register(structures)
		preload("res://addons/structures/storage_catalog.gd").register(structures)
		preload("res://addons/structures/door_catalog.gd").register(structures)
		preload("res://addons/structures/window_catalog.gd").register(structures)
		var placement:RefCounted=ClassDB.instantiate("NativePrefabPlacement")
		var asset:Resource=preload("res://addons/structures/workshop_catalog.gd").village_shop()
		var placed:Dictionary=placement.place(structures.blocks,asset,Vector3i(0,0,20),0,structures.model_collections(),[])
		check(placed.get("ok",false),"unchanged approved shop is built from production destructible blocks")
		game.camera.position=Vector3(.5,2.65,20.5);await frames(15)
		for item in [1,2,3,4,5,6,406,0]:
			await equip(item);await compare("inside_shop_"+str(item))
		structures.free();await frames()
	game.camera.position=Vector3(0,1.65,0);await equip(6)
	var effect:Node3D=game.tool_view.human.torch_effects
	for child:Node in effect.get_children():
		if child is GeometryInstance3D:
			check(child in game.first_person_view.meshes.equipment,"torch effect is protected: "+String(child.name))
			check(is_equal_approx(child.get_instance_shader_parameter("first_person_depth_scale"),.01),"torch effect uses native depth protection: "+String(child.name))
	var original_material:Material=effect.get_node("Flame").material_override
	var late:=MeshInstance3D.new();late.name="LateEquipmentEffect";late.mesh=SphereMesh.new();late.material_override=StandardMaterial3D.new();effect.add_child(late);await frames()
	check(late in game.first_person_view.meshes.equipment and late.material_override.use_z_clip_scale,"late-added held geometry automatically inherits protection")
	late.free();await frames()
	var wall:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(5,5,.02);wall.mesh=box
	var material:=StandardMaterial3D.new();material.albedo_color=Color("35363b");wall.material_override=material
	wall.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;game.camera.add_child(wall);wall.position=Vector3(0,0,-.25)
	game.first_person_view.set_enabled(false,false);var hidden:=await photo("torch_wall_off")
	game.first_person_view.set_enabled(true,false);var visible:=await photo("torch_wall_on")
	check(orange_pixels(visible)>orange_pixels(hidden)+100,"torch flame and embers remain visible in front of a nearby wall")
	check(effect.get_node("Flame").material_override==original_material,"protection does not replace the torch effect material or animation owner")
	material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA;material.albedo_color=Color(.2,.3,.8,.98)
	var through_glass:=await photo("torch_glass_on")
	check(orange_pixels(through_glass)>100,"transparent world geometry cannot sort over the protected torch flame")
	game.first_person_view.set_shadows_enabled(true,false);await frames()
	for child:Node in effect.get_children():
		if child is GeometryInstance3D:check(child.layers==1<<18,"optional detailed mode also includes "+String(child.name))
	game.first_person_view.set_shadows_enabled(false,false);wall.free()
	game.free();structures=null;assets=null;await frames(2)
	results.checks=checks;results.failures=failures
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	print("FIRST_PERSON_PARITY checks=",checks," failures=",failures);quit(1 if failures else 0)
