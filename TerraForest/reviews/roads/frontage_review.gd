extends Node
const Plan=preload("res://reviews/roads/frontage_plan.gd")
var game:Node
var plans:Dictionary={}
var current:Dictionary={}
var trial:=true
var busy:=true
var review_ready:=false
var error:=""
var street_index:=0
var automatic:=true
var banner:=Label.new()
var worker:Thread
func _ready()->void:
	var arguments:=PackedStringArray(OS.get_cmdline_user_args())
	if not "--temporary" in arguments or not "--world-slot=Road_Grade_Preview" in arguments:
		push_error("Road review requires its isolated temporary slot");get_tree().quit(2);return
	var layer:=CanvasLayer.new();layer.layer=70;add_child(layer)
	var panel:=PanelContainer.new();panel.position=Vector2(520,24);layer.add_child(panel)
	var style:=StyleBoxFlat.new();style.bg_color=Color(.025,.045,.05,.94)
	style.content_margin_left=16;style.content_margin_right=16;style.content_margin_top=10;style.content_margin_bottom=10
	panel.add_theme_stylebox_override("panel",style);panel.add_child(banner)
	banner.add_theme_font_size_override("font_size",18);banner.add_theme_color_override("font_color",Color("f3deb0"))
	if automatic:prepare.call_deferred()
func _exit_tree()->void:
	if worker!=null and worker.is_started():worker.wait_to_finish()
func status(message:String)->void:
	banner.text="ROAD-GRADING PREVIEW · Seed 1703 · Nothing is saved\n"+message
func fail(message:String)->bool:
	error=message;busy=false;review_ready=false;status("REVIEW STOPPED · "+message);push_error(message);return false
func wait_for(predicate:Callable,seconds:float=90)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	return predicate.call()
func prepare()->bool:
	status("Surveying native road corridors and unchanged building designs...")
	worker=Thread.new()
	if worker.start(Plan.build)!=OK:worker=null;return fail("Planning worker could not start")
	while worker.is_alive():await get_tree().process_frame
	plans=worker.wait_to_finish();worker=null
	if not plans.get("ok",false):return fail(plans.get("reason","Planning failed"))
	return await show_variant(true)
func show_variant(enabled:bool)->bool:
	busy=true;review_ready=false;trial=enabled
	if is_instance_valid(game):
		status("Closing the temporary comparison; no saves are written...")
		game.review_input_active=false;game.set_process_unhandled_input(false);game.shutdown_requested=true
		if not await game.terrain.shutdown_after_edits():return fail("Temporary world did not finish closing")
		game.free();game=null;await get_tree().process_frame
	current=plans.trial if trial else plans.baseline
	status("Baking %s roads, surrounding terrain and existing building sites..."%["PROPOSED" if trial else "ORIGINAL"])
	game=preload("res://reviews/roads/frontage_world.gd").new()
	game.temporary_world=true;game.model_region_paging=false;game.player_view.settings_path=""
	game.background_fps=60
	var spawn:Vector3=current.center+Vector3(6,0,-20)
	game.configure_generation_spawn(spawn)
	var packets:=Plan.Earthworks.packets(current.works.segments)
	var digest:String=preload("res://addons/world_runtime/survey_cache.gd").digest(var_to_bytes(packets)).hex_encode()
	if not game.terrain.backend.configure_initial_earthworks(packets,digest):game.free();game=null;return fail("Initial native terrain bake rejected")
	add_child(game);game.set_process_unhandled_input(false)
	if not await wait_for(func():return not game.loading_active and not game.needs_floor_spawn):return fail("Terrain loading timed out")
	game.set_physics_process(false)
	var transaction:RefCounted=ClassDB.instantiate("NativePrefabPlacement")
	for index in current.lots.size():
		var lot:Dictionary=current.lots[index]
		status("Placing unchanged building %d / %d and its interiors..."%[index+1,current.lots.size()])
		if not game.foundation_check.begin(game.terrain,lot.asset,lot.origin,lot.rotation):return fail("Building survey rejected")
		var deadline:=Time.get_ticks_msec()+15000
		while game.foundation_check.status=="checking" and Time.get_ticks_msec()<deadline:
			game.foundation_check.tick(game.terrain);await get_tree().process_frame
		if game.foundation_check.status!="supported":return fail("Generated terrain does not support "+lot.label)
		var published:Dictionary=transaction.place(game.structures.blocks,lot.asset,lot.origin,lot.rotation,game.structures.model_collections(),[])
		if not published.get("ok",false):return fail("Building publication failed: "+str(published))
	var plates:PackedInt32Array=current.block_paving.records
	for offset in range(0,plates.size(),4096):
		if not game.structures.blocks.set_cells(plates.slice(offset,mini(offset+4096,plates.size()))):return fail("Individual sidewalk plate publication failed")
		await get_tree().process_frame
	game.structures.blocks.flush_bakes()
	game.ground_cover._exclusion_changed(current.works.bounds)
	if not game.session_menu.developer:game.session_menu.toggle_developer()
	game.player_hud.equip(3);game.structure_shape=1;game.structure_material=0;game.structure_rotation=0;game.structure_prefab_index=-1
	if not await visit(0):return false
	game.set_process_unhandled_input(true);game.set_physics_process(true)
	game.review_input_active=true
	preload("res://addons/world_runtime/mouse_ownership.gd").set_mode(game,Input.MOUSE_MODE_CAPTURED)
	busy=false;review_ready=true;instructions()
	print("ROAD_FRONTAGE_REVIEW_READY trial=",trial," center=",current.center)
	return true
func instructions()->void:
	status(("PROPOSED: 52 m near-level streets; smooth end transitions" if trial else "ORIGINAL: locally rounded road nodes; unchanged placement")+"\nF6: compare/rebuild · F7: other street · Right click: place · Left click: remove")
func visit(index:int)->bool:
	street_index=index
	var point:Vector3=current.center+Vector3(6,0,-20 if index==0 else 28)
	var elevation:=NAN
	for road:Dictionary in current.roads:
		if absf(road.start.z-(point.z-4))>.01 or absf(road.finish.z-road.start.z)>.01 or road.finish.x-road.start.x<2 or point.x<road.start.x or point.x>road.finish.x:continue
		var fraction:float=(point.x-road.start.x)/(road.finish.x-road.start.x)
		var base:int=road.curve_index*4
		elevation=((road.coefficients[base]*fraction+road.coefficients[base+1])*fraction+road.coefficients[base+2])*fraction+road.coefficients[base+3]
	if not is_finite(elevation):return fail("Street destination has no grade")
	game.teleport(point,elevation+.2)
	if not await wait_for(func():return not game.loading_active and not game.needs_floor_spawn and not game.waiting_spawn):return fail("Street collision loading timed out")
	game.yaw=0;game.pitch=-.38;game.player.rotation.y=0;game.camera.rotation=Vector3(game.pitch,0,0)
	return true
func _input(event:InputEvent)->void:
	if not review_ready or busy or not event is InputEventKey or not event.pressed or event.echo:return
	if game.session_menu.visible_ui() or game.player_hud.inventory_open:return
	if event.physical_keycode==KEY_F6:
		get_viewport().set_input_as_handled();show_variant(not trial)
	elif event.physical_keycode==KEY_F7:
		get_viewport().set_input_as_handled();busy=true;await visit(1-street_index);busy=false
