extends SceneTree

class Fixture extends Node3D:
	var camera:=Camera3D.new()
	var tool_view=load("res://addons/player_runtime/tool_view.gd").new()
	var player_view:={"active":false}
	var world_vehicle:={"driving":false}
	var session_menu:={"first_person_toggle":CheckButton.new(),"first_person_shadows_toggle":CheckButton.new()}
	var temporary_world:=true
	var loading_active:=false
	var shutdown_requested:=false
	var first_person_view:Node
	func _ready()->void:
		add_child(camera);camera.position=Vector3(0,1.65,0);camera.near=.08
		camera.add_child(tool_view)
		add_child(session_menu.first_person_toggle);session_menu.first_person_toggle.hide()
		add_child(session_menu.first_person_shadows_toggle);session_menu.first_person_shadows_toggle.hide()
		if FileAccess.file_exists("res://addons/player_runtime/first_person_view.gd"):
			first_person_view=load("res://addons/player_runtime/first_person_view.gd").new();first_person_view.settings_path=""
			add_child(first_person_view);first_person_view.prepare(self)

var game:Fixture
var folder:=""
var captures:Array[String]=[]

func _initialize()->void:run.call_deferred()
func frames(count:int=5)->void:
	for frame in count:await process_frame
func photo(label:String)->void:
	await frames();await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png(folder.path_join(label+".png"))!=OK:quit(1);return
	captures.append(label)
func equip(item:int)->void:
	game.tool_view.equip(item)
	var human:Node=game.tool_view.human
	human.animation_player.play(human.clips[human._motion_clip("Idle")],0);human.animation_player.advance(.2)
	human.torch_effects.set_process(false)
	if item==6:human.torch_effects.advance(.4)
	await frames()
func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--checkpoint-evidence="):folder=argument.trim_prefix("--checkpoint-evidence=")
	if folder.is_empty():quit(2);return
	DirAccess.make_dir_recursive_absolute(folder)
	var environment:=Environment.new();environment.background_mode=Environment.BG_SKY
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.ambient_light_color=Color("a6b8cf");environment.ambient_light_energy=.35
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	var sky:=Sky.new();sky.radiance_size=Sky.RADIANCE_SIZE_128;sky.sky_material=ProceduralSkyMaterial.new();environment.sky=sky
	environment.fog_enabled=true;environment.fog_density=.00055;environment.fog_light_color=Color("a7c4cd")
	var host:=WorldEnvironment.new();host.environment=environment;root.add_child(host)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-90,0,0);sun.shadow_enabled=true;sun.directional_shadow_max_distance=256;root.add_child(sun)
	game=Fixture.new();root.add_child(game);game.tool_view.set_process(false);game.tool_view.human.set_process(false)
	await equip(1);await photo("outdoors_pickaxe")
	var assets:RefCounted=load("res://addons/vegetation/assets.gd").new()
	if not assets.build():quit(1);return
	assets.uniforms(game.camera.global_position,Vector3.UP,0,0,448)
	var tree:=Node3D.new();root.add_child(tree)
	for kind in [0,3]:
		var node:=MultiMeshInstance3D.new();node.multimesh=MultiMesh.new();node.multimesh.transform_format=MultiMesh.TRANSFORM_3D
		node.multimesh.use_custom_data=true;node.multimesh.mesh=assets.meshes[kind];node.multimesh.instance_count=1
		node.multimesh.set_instance_transform(0,Transform3D(Basis.IDENTITY,Vector3(2,0,-2)));node.multimesh.set_instance_custom_data(0,Color(.25,1,0,0))
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind==0 else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		tree.add_child(node)
	await photo("under_tree_pickaxe");await equip(6);await photo("under_tree_torch")
	tree.free();await frames()
	var structures:Node3D=load("res://addons/structures/structures_world.gd").new();root.add_child(structures)
	if not structures.prepare():quit(1);return
	for catalog in ["furniture","storage","door","window"]:load("res://addons/structures/"+catalog+"_catalog.gd").register(structures)
	var placement:RefCounted=ClassDB.instantiate("NativePrefabPlacement")
	var asset:Resource=load("res://addons/structures/workshop_catalog.gd").village_shop()
	var placed:Dictionary=placement.place(structures.blocks,asset,Vector3i(0,0,20),0,structures.model_collections(),[])
	if not placed.get("ok",false):quit(1);return
	game.camera.position=Vector3(.5,2.65,20.5);await frames(15)
	for item in [1,2,3,4,5,6,406,0]:
		await equip(item);await photo("inside_shop_"+str(item))
	sun.light_energy=0;environment.ambient_light_energy=.05;await equip(6);await photo("night_torch")
	var lamp:SpotLight3D=load("res://addons/player_runtime/headlamp.gd").new();game.camera.add_child(lamp);lamp.toggle()
	await equip(1);await photo("night_headlamp")
	var baseline:bool=game.first_person_view==null
	game.free();structures.free();assets=null;await frames(2)
	var sources:={}
	for path in ["res://addons/characters/runtime/human_view.gd","res://addons/player_runtime/tool_view.gd","res://addons/characters/runtime/torch_effects.gd","res://addons/characters/runtime/assets/Human.r11.glb"]:sources[path]=FileAccess.get_sha256(path)
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"historical_runtime":baseline,"project":ProjectSettings.globalize_path("res://"),"source_sha256":sources,"captures":captures,"engine":Engine.get_version_info()},"  "))
	print("FIRST_PERSON_CHECKPOINT captures=",captures.size()," historical=",baseline);quit()
