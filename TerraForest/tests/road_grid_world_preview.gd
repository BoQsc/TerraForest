extends "res://tests/combined_resource_route.gd"
const Earthworks=preload("res://addons/world_runtime/generation_earthworks.gd")
var banner:=Label.new()
var placed:Array[Vector3i]=[]
var road:Dictionary
var view:=SubViewport.new()
func _process(_delta:float)->bool:
	if is_instance_valid(game):game.app_focused=true
	return false
func screenshot(label:String,overview:bool=false)->void:
	var center:Vector3=(road.start+road.finish)*.5
	game.camera.global_position=center+Vector3(0,10,17) if overview else center+Vector3(-3,2.1,6.5)
	game.camera.look_at(center+Vector3(0,.4,0))
	game.structures.blocks.flush_bakes()
	for frame in 120:await process_frame
	game.set_process(false);game.shape_preview.hide();game.prefab_preview.hide();game.model_tool.preview.hide()
	check(not game.loading_active and not game.loading_layer.visible,"capture contains gameplay, not the loading screen")
	RenderingServer.force_draw(false)
	await RenderingServer.frame_post_draw
	view.get_texture().get_image().save_png(evidence.path_join(label+".png"))
	game.set_process(true)
func samples()->Array:
	var result:Array=[]
	for across in range(ceili(road.start.x),floori(road.finish.x)):
		for lateral in [-2,0,2]:
			var cell:=Vector3i(across,35,roundi(road.start.z)+lateral)
			var fit:Dictionary=game.structures.blocks.placement_support(AABB(Vector3(cell),Vector3.ONE),Vector3(cell)+Vector3(.5,0,.5),true,true,[game.player.get_rid()])
			result.append({"cell":cell,"support":fit})
	return result
func summarize(rows:Array)->Dictionary:
	var result:={"cells":rows.size(),"within_15cm":0,"over_50cm":0,"mean_gap":0.0,"worst_gap":0.0}
	for row:Dictionary in rows:
		check(row.support.ok and row.support.hits==9,"all footprint support samples hit rendered collision")
		var gap:float=row.support.gap
		result.within_15cm+=int(gap<=.15)
		result.over_50cm+=int(gap>.5)
		result.mean_gap+=gap/rows.size()
		result.worst_gap=maxf(result.worst_gap,gap)
	return result
func place_examples()->void:
	for across in [1007,1011,1015]:
		var point:=Vector3(across+.5,35.5,1093.5)
		game.player.position=point+Vector3(0,0,3)
		game.camera.global_position=point+Vector3(0,1.8,2.8);game.camera.look_at(point-Vector3(0,.5,0))
		var target:Dictionary=game._structure_target(false)
		check(target.get("placement_ok",false),"ordinary grid targeting accepts comparison brick "+str(across))
		if not target.get("placement_ok",false):print("TARGET ",target);continue
		game._edit_structure(false)
		check(game.structures.blocks.get_cell(target.target)==1,"real click handler places the brick without grid offsets")
		placed.append(target.target)
		print("PREVIEW_BRICK ",banner.text," ",target)
	game.structures.blocks.flush_bakes()
func run()->void:
	var arguments:=PackedStringArray(OS.get_cmdline_user_args())
	if not "--snapshot-readonly" in arguments or not "--temporary" in arguments:quit(2);return
	evidence="res://reports/road_grid_trial"
	var prepared:Dictionary=FileAccess.open(evidence.path_join("selected.bin"),FileAccess.READ).get_var()
	road=prepared.road
	view.size=Vector2i(1920,1080);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";view.add_child(game)
	if not check(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,90),"read-only saved world loads"):await finish();return
	check(game.terrain.backend.readonly_snapshot and game.terrain.save_slot=="Wild_Hills","preview cannot save over Wild_Hills")
	check(game.world_identity.text=="Wild_Hills · Seed 1703","HUD identifies the actual loaded world")
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.session_menu.set_open(false)
	game.teleport(Vector3(1010,35,1097),36)
	if not check(await wait_for(func():return not game.loading_active and not game.loading_layer.visible and not game.waiting_spawn and game._placement_collision_ready(AABB(Vector3(1002,34,1089),Vector3(19,5,9))),60),"settlement road and landscape have finished loading"):await finish();return
	game.needs_floor_spawn=false
	if not game.session_menu.developer:game.session_menu.toggle_developer()
	game.player_hud.equip(3);game.structure_shape=1;game.structure_material=0;game.structure_rotation=0;game.structure_prefab_index=-1
	var layer:=CanvasLayer.new();view.add_child(layer);layer.add_child(banner)
	banner.position=Vector2(525,35);banner.add_theme_font_size_override("font_size",22);banner.add_theme_color_override("font_color",Color("f3deb0"))
	banner.text="BASELINE · Wild_Hills / seed 1703 · Road grading trial OFF"
	var before:=samples()
	await place_examples()
	await screenshot("before")
	await screenshot("before_overview",true)
	for cell:Vector3i in placed:game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,0]))
	placed.clear();game.structures.blocks.flush_bakes()
	game.player.position=Vector3(1010,36,1101)
	var packets:Array=Earthworks.packets(prepared.trial.segments)
	for index in packets.size():
		var segment:Dictionary=prepared.trial.segments[index]
		if not check(game.terrain.edit(packets[index],segment.start.min(segment.finish),segment.start.max(segment.finish)),"trial density stamp "+str(index)):await finish();return
		if not check(await wait_for(func():return not game.terrain.pending_edit,15),"trial stamp settled"):await finish();return
	if not check(await wait_for(func():return game._placement_collision_ready(AABB(Vector3(1002,34,1089),Vector3(19,5,9))),45),"trial collision matches the revised terrain"):await finish();return
	for frame in 30:await process_frame
	banner.text="OPTIONAL PREVIEW · Wild_Hills / seed 1703 · NOT SAVED"
	var after:=samples()
	await place_examples()
	await screenshot("after")
	await screenshot("after_overview",true)
	var before_summary:=summarize(before)
	var after_summary:=summarize(after)
	check(after_summary.within_15cm>before_summary.within_15cm and after_summary.mean_gap<before_summary.mean_gap,"whole-stretch contact improves, not only the featured brick")
	FileAccess.open(evidence.path_join("world_contact.json"),FileAccess.WRITE).store_string(JSON.stringify({"road":road,"before":before,"after":after,"before_summary":before_summary,"after_summary":after_summary},"  "))
	var floating:=Vector3i(1010,42,1093)
	game.structures.blocks.set_cells(PackedInt32Array([floating.x,floating.y,floating.z,1]));game.structures.blocks.flush_bakes()
	await wait_for(func():return game._placement_collision_ready(AABB(Vector3(floating),Vector3.ONE*2)),10)
	game.camera.global_position=Vector3(floating)+Vector3(.5,.5,3);game.camera.look_at(Vector3(floating)+Vector3.ONE*.5)
	var aerial:Dictionary=game._structure_target(false)
	check(aerial.get("placement_ok",false) and aerial.target==floating+Vector3i(0,0,1),"intentional floating construction keeps its exact grid adjacency")
	await finish()
func finish()->void:
	if is_instance_valid(game):
		game.shutdown_requested=true
		check(await game.terrain.shutdown_after_edits(),"read-only preview shuts down without saving")
		game.free();await process_frame
	print("ROAD_GRID_WORLD_PREVIEW failures=",failures)
	quit(1 if failures else 0)
