# SPDX-License-Identifier: 0BSD
extends SceneTree
const Clothing=preload("res://addons/characters/wearables/clothing.gd")
var folder:="res://reports/woven_clothes"
var failures:=0
var checks:=0

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--evidence="):folder=argument.trim_prefix("--evidence=")
	run.call_deferred()

func photograph(label:String)->void:
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))

func run()->void:
	DirAccess.make_dir_recursive_absolute(folder)
	for id:int in Clothing.ITEMS:
		var mesh:ArrayMesh=Clothing.ITEMS[id];var valid:=true;var triangles:=0
		for s in mesh.get_surface_count():
			var arrays:=mesh.surface_get_arrays(s)
			var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var bones:PackedInt32Array=arrays[Mesh.ARRAY_BONES]
			var weights:PackedFloat32Array=arrays[Mesh.ARRAY_WEIGHTS]
			triangles+=arrays[Mesh.ARRAY_INDEX].size()/3
			valid=valid and bones.size()==vertices.size()*4 and weights.size()==bones.size()
			for v in vertices.size():
				var total:=0.0
				for b in 4:
					valid=valid and bones[v*4+b]>=0 and bones[v*4+b]<10 and weights[v*4+b]>=0
					total+=weights[v*4+b]
				# Godot stores each influence as UNORM16; four rounded values can
				# differ from one by at most four quantization steps.
				valid=valid and vertices[v].is_finite() and absf(total-1.0)<=4.0/65535.0
		check(valid and triangles<5000,"%d has finite geometry and normalized named-bone weights under 5000 triangles"%id)
		var drop:Mesh=load("res://addons/player_runtime/art/drops/%d.res"%id)
		check(drop!=null and absf(drop.get_aabb().get_longest_axis_size()-.35)<.001,"%d has a matching normalized ground-item mesh"%id)
	var hud=preload("res://addons/player_runtime/player_hud.gd").new();root.add_child(hud)
	# Same binding as the world player_view.prepare, exercised against real storage.
	var human=preload("res://addons/characters/runtime/human_view.gd").new();root.add_child(human);human.set_process(false);human.hide()
	hud.character_panel.equipment_presented.connect(human.clothing.set_slots)
	hud.set_open(true);hud.show_side("Character")
	await process_frame
	var clothes:Node=hud.character_panel.clothing
	check(clothes!=null and clothes.worn==PackedInt32Array([0,0,0]),"empty equipment preserves the base outfit")
	await photograph("01-base")
	var grant:Dictionary=hud.inventory.grant_items(PackedInt64Array([204,9]),hud.inventory.snapshot().revision)
	check(grant.ok,"plant fibres enter ordinary inventory")
	var crafting=preload("res://addons/player_runtime/crafting.gd")
	for index in crafting.RECIPES.size():
		if crafting.RECIPES[index].outputs[0] in [301,302,303]:
			check(crafting.craft(hud.inventory,index,1,hud.inventory.snapshot().revision).ok,"paid recipe crafts "+crafting.RECIPES[index].title)
	check(not hud.inventory.can_afford(PackedInt64Array([204,1]),hud.inventory.snapshot().revision).ok,"three recipes consume exactly nine plant fibres")
	hud.refresh()
	for id in [301,302,303]:
		var source:=-1
		for i in 32:
			if hud.inventory.snapshot().slots[i].item==id:source=i;break
		var data:Dictionary=hud.drag_data("player",source)
		check(not hud.character_panel.accepts_drag("equipment",(id-300)%3,data),"wrong slot rejects %d"%id)
		hud.character_panel.drop_stack("equipment",id-301,data)
		check(clothes.worn[id-301]==id and human.clothing.worn[id-301]==id,"equip %d updates portrait and gameplay body"%id)
		check(not hud.character_panel.accepts_drag("equipment",id-301,data),"stale drag cannot duplicate %d"%id)
	await photograph("02-equipped")
	var saved:PackedByteArray=hud.equipment.capture_storage_snapshot()
	var saved_inventory:PackedByteArray=hud.capture_snapshot()
	for id in [301,302,303]:
		var data:Dictionary=hud.character_panel.drag_data("equipment",id-301)
		hud.drop_stack("player",29+id-301,data)
	check(clothes.worn==PackedInt32Array([0,0,0]) and human.clothing.worn==clothes.worn,"unequip removes all three meshes from both views")
	for item:Dictionary in clothes.covered:check(item.node.visible==item.visible,"base visibility restored for "+String(item.node.name))
	check(hud.equipment.restore_storage_snapshot(saved),"existing binary equipment snapshot restores without a schema change")
	check(hud.restore_snapshot(saved_inventory),"matching backpack snapshot restores without duplicating clothing")
	check(clothes.worn==PackedInt32Array([301,302,303]) and human.clothing.worn==clothes.worn,"refresh after restore reapplies clothes to both views")
	human.set_third_person(false)
	check(not human.clothing.garments[301].visible and human.clothing.garments[302].visible and human.clothing.garments[303].visible,"first person hides the hood and keeps body/feet")
	human.set_third_person(true)
	check(human.clothing.garments[301].visible,"third person restores the worn hood")
	var count:int=hud.character_panel.portrait.renders
	for i in 4:hud.refresh()
	check(count==hud.character_panel.portrait.renders,"unchanged equipment does not rerender the portrait")
	hud.show_side("Backpack");count=hud.character_panel.portrait.renders
	for i in 5:await process_frame
	check(count==hud.character_panel.portrait.renders,"hidden portrait remains idle")
	hud.free();human.free()
	await gallery()
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED,"review never captures the pointer")
	print("WOVEN_CLOTHES checks=",checks," failures=",failures);quit(1 if failures else 0)

func gallery()->void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(1600,1050);viewport.own_world_3d=true;viewport.msaa_3d=Viewport.MSAA_4X;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var env:=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color("1b272c")
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color("b7cad2");env.environment.ambient_light_energy=.7;viewport.add_child(env)
	var key:=DirectionalLight3D.new();key.rotation_degrees=Vector3(-35,-30,0);key.light_energy=1.25;viewport.add_child(key)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-25,150,0);fill.light_energy=.6;viewport.add_child(fill)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=3.45;camera.position=Vector3(0,1.1,5);viewport.add_child(camera);camera.look_at(Vector3(0,1.05,0));camera.current=true
	var actors:Array=[]
	for i in 3:
		var actor=preload("res://addons/characters/runtime/human_view.gd").new();viewport.add_child(actor);actor.position=Vector3((i-1)*1.2,0,0);actor.rotation=Vector3(0,[.22,PI*.5,PI+.25][i],0);actor.set_process(false);actor.set_third_person(true)
		actor.clothing.set_slots([{"item":301,"count":1},{"item":302,"count":1},{"item":303,"count":1}]);actors.append(actor)
	for pose in ["Idle","Walk","Run","Player_Crouch","FP_Pickaxe_Fresh_Swing","FP_Unarmed_Punch"]:
		for actor in actors:
			if pose=="FP_Pickaxe_Fresh_Swing":actor.equip(1)
			else:actor.equip(0)
			var clip:String=actor.clips[pose];actor.animation_player.play(clip,0)
			actor.animation_player.advance(actor.animation_player.get_animation(clip).length*.5);actor.animation_player.pause()
		for i in 3:await process_frame
		await RenderingServer.frame_post_draw
		viewport.get_texture().get_image().save_png(folder.path_join("fit-"+pose+".png"))
		check(viewport.get_texture().get_image().get_pixel(0,0).get_luminance()>.01,"rendered front/side/back "+pose)
	for actor in actors:
		actor.clothing.set_slots([]);actor.equip(0);actor.animation_player.play(actor.clips["Player_Crouch"],0);actor.animation_player.advance(actor.animation_player.get_animation(actor.clips["Player_Crouch"]).length*.5);actor.animation_player.pause()
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(folder.path_join("baseline-crouch.png"))
	viewport.free()
