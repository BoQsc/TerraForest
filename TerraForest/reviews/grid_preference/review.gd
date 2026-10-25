extends Node
const Mouse=preload("res://addons/world_runtime/mouse_ownership.gd")
var game:Node
var view:Viewport
var automatic:=false
var busy:=false
var failures:=0
var quality_failures:=0
var evidence:="res://reports/road_normalization/playtest"
func check(ok:bool,label:String)->bool:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
	return ok
func wait_for(predicate:Callable,seconds:int=60)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	return predicate.call()
func _ready()->void:
	var slot:=""
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--world-slot="):slot=argument.trim_prefix("--world-slot=")
		automatic=automatic or argument=="--grid-review-auto"
	if not slot.begins_with("GridPreference_1703_") or not FileAccess.file_exists("user://worlds/"+slot+".trw"):
		push_error("This review requires its separately generated GridPreference_1703 world.");get_tree().quit(2);return
	DirAccess.make_dir_recursive_absolute(evidence)
	view=get_viewport()
	if automatic:
		var offscreen:=SubViewport.new();offscreen.size=Vector2i(1920,1080);offscreen.own_world_3d=true;offscreen.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(offscreen);view=offscreen
	game=load("res://demo/world.tscn").instantiate();game.background_fps=60
	if automatic:game.player_view.settings_path="";game.temporary_world=true
	view.add_child(game) if automatic else add_child(game)
	if not check(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,90),"generated review world loads"):await finish();return
	var connected:bool=game.world_recipe.store.decode(game.world_recipe.store.capture_snapshot()).get("road_grid",0)>=2
	check(game.world_recipe.store.decode(game.world_recipe.store.capture_snapshot()).get("road_grid",0)>0 and game.terrain.backend.world_generator==23,"saved terrain and road defaults both enabled")
	check(game.prefer_block_burial,"bounded block embedding preference is enabled")
	if not game.session_menu.developer:game.session_menu.toggle_developer()
	game.player_hud.equip(3);game.structure_shape=1;game.structure_material=0;game.structure_rotation=0;game.structure_prefab_index=-1
	if not await visit(false,connected and not automatic):await finish();return
	if not automatic:print("GRID_PREFERENCE_PLAYTEST_READY slot=",slot," F6=old road F7=old terrain F8=reported regional road F9=reported shoulder");return
	var contacts:Array=[]
	for across in range(1004,1018):
		for lateral in [-2,0,2]:
			var point:=Vector3(across,35,1093+lateral)
			var fit:Dictionary=game.structures.blocks.placement_support(AABB(point,Vector3.ONE),point+Vector3(.5,0,.5),true,true,[game.player.get_rid()],true)
			check(fit.get("ok",false) and fit.get("hits",0)==9,"old road footprint resolves all collision samples")
			if fit.get("gap",INF)>.10 or fit.get("burial",INF)>.25:quality_failures+=1
			contacts.append({"cell":point,"fit":fit})
	for across in [1007,1011,1015]:
		var point:=Vector3(across+.5,35.5,1093.5)
		game.player.position=point+Vector3(0,0,3)
		game.camera.global_position=point+Vector3(0,1.8,2.8);game.camera.look_at(point-Vector3(0,.5,0))
		var target:Dictionary=game._structure_target(false)
		if check(target.get("placement_ok",false),"ordinary placement on generated road"):
			game._edit_structure(false);check(game.structures.blocks.get_cell(target.target)==1,"click places previewed integer cell")
	game.structures.blocks.flush_bakes()
	game.camera.global_position=Vector3(1008,37.6,1099.5);game.camera.look_at(Vector3(1011,35.9,1093))
	await photograph("road")
	if not await visit(true):await finish();return
	var point:=Vector3(800,50,1312)
	var natural:Dictionary=game.structures.blocks.placement_support(AABB(point,Vector3.ONE),point+Vector3(.5,0,.5),true,true,[game.player.get_rid()],true)
	check(natural.get("ok",false) and natural.hits==9,"natural terrain footprint resolves")
	if natural.get("gap",INF)>.10 or natural.get("burial",INF)>.25:quality_failures+=1
	game.camera.global_position=point+Vector3(.5,1.8,3);game.camera.look_at(point+Vector3(.5,0,.5))
	var target:Dictionary=game._structure_target(false)
	if check(target.get("placement_ok",false),"ordinary placement on normalized natural terrain"):game._edit_structure(false)
	game.structures.blocks.flush_bakes();await photograph("terrain")
	var reported:Dictionary={}
	if connected:
		if not await visit(false,true):await finish();return
		var cell:=Vector3(1076,47,838)
		reported=game.structures.blocks.placement_support(AABB(cell,Vector3.ONE),cell+Vector3(.5,0,.5),true,true,[game.player.get_rid()],true)
		check(reported.get("ok",false) and reported.get("hits",0)==9,"reported regional-road cell resolves actual collision")
		if reported.get("gap",INF)>.10 or reported.get("burial",INF)>.25:quality_failures+=1
		game.camera.global_position=cell+Vector3(.5,1.8,3);game.camera.look_at(cell+Vector3(.5,.1,.5))
		var placement:Dictionary=game._structure_target(false)
		if check(placement.get("placement_ok",false),"ordinary click on newly generated reported road"):game._edit_structure(false)
		game.structures.blocks.flush_bakes();await photograph("reported_road")
	if not await visit(false,false,true):await finish();return
	var shoulder_cell:=Vector3(953,35,1137)
	var shoulder:Dictionary=game.structures.blocks.placement_support(AABB(shoulder_cell,Vector3.ONE),shoulder_cell+Vector3(.5,0,.5),true,true,[game.player.get_rid()],true)
	check(shoulder.get("ok",false) and shoulder.get("hits",0)==9,"reported shoulder resolves actual collision")
	if shoulder.get("gap",INF)>.10 or shoulder.get("burial",INF)>.25:quality_failures+=1
	game.camera.global_position=shoulder_cell+Vector3(.5,1.8,3);game.camera.look_at(shoulder_cell+Vector3(.5,.1,.5))
	var shoulder_target:Dictionary=game._structure_target(false)
	if check(shoulder_target.get("placement_ok",false),"ordinary click on newly generated shoulder"):game._edit_structure(false)
	game.structures.blocks.flush_bakes();await photograph("reported_shoulder")
	FileAccess.open(evidence.path_join("contact.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":slot,"failures":failures,"quality_failures":quality_failures,"quality_passed":quality_failures==0,"quality_limits":{"gap":.10,"burial":.25},"road":contacts,"terrain":natural,"reported_road":reported,"reported_shoulder":shoulder,"burial_correction":true},"  "))
	print("GRID_PREFERENCE_QUALITY ","PASS" if quality_failures==0 else "REJECTED"," failing footprints=",quality_failures," / ",45 if connected else 44,"; engineering checks do not override this result")
	await finish()
func _process(_delta:float)->void:
	if automatic and is_instance_valid(game):game.app_focused=true
func visit(natural:bool,reported:bool=false,shoulder:bool=false)->bool:
	busy=true;game.session_menu.set_open(false);game.set_physics_process(false);game._clear_motion()
	var position:=Vector3(800.5,52,1315.5) if natural else Vector3(1008,37,1098)
	if reported:position=Vector3(1074.452,48.3,842.499)
	if shoulder:position=Vector3(951.6663,36.5,1139.778)
	game.teleport(position,position.y)
	var bounds:=AABB(Vector3(798,47,1310),Vector3(6,8,8)) if natural else AABB(Vector3(1002,33,1089),Vector3(19,7,11))
	if reported:bounds=AABB(Vector3(1072,44,833),Vector3(10,8,13))
	if shoulder:bounds=AABB(Vector3(949,33,1133),Vector3(10,8,12))
	var ready:=await wait_for(func():return not game.loading_active and not game.loading_layer.visible and not game.waiting_spawn and game._placement_collision_ready(bounds),90)
	check(ready,"old problem location finishes loading")
	game.yaw=0 if natural else -.35;game.pitch=-.25;game.player.rotation.y=game.yaw;game.camera.rotation=Vector3(game.pitch,0,0)
	if reported:game.yaw=-.5225;game.pitch=-.3025;game.player.rotation.y=game.yaw;game.camera.rotation=Vector3(game.pitch,0,0)
	if shoulder:game.yaw=-.755;game.pitch=-.5625;game.player.rotation.y=game.yaw;game.camera.rotation=Vector3(game.pitch,0,0)
	game.needs_floor_spawn=false;game._clear_motion();game.set_physics_process(not automatic)
	if not automatic:Mouse.set_mode(game,Input.MOUSE_MODE_CAPTURED)
	busy=false;return ready
func _input(event:InputEvent)->void:
	if automatic or busy or not is_instance_valid(game):return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_F6,KEY_F7,KEY_F8,KEY_F9]:
		get_viewport().set_input_as_handled();visit(event.physical_keycode==KEY_F7,event.physical_keycode==KEY_F8,event.physical_keycode==KEY_F9)
func photograph(name:String)->void:
	game.set_process(false);game.shape_preview.hide();game.prefab_preview.hide()
	for frame in 60:await get_tree().process_frame
	await RenderingServer.frame_post_draw
	check(view.get_texture().get_image().save_png(evidence.path_join(name+".png"))==OK,"captured actual "+name+" placement")
	game.set_process(true)
func finish()->void:
	if is_instance_valid(game):
		game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"review closes cleanly");game.queue_free();await get_tree().process_frame
	print("GRID_PREFERENCE_REVIEW failures=",failures);get_tree().quit(1 if failures else 0)
