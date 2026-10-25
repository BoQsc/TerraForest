extends "res://tests/combined_resource_route.gd"
const Earthworks=preload("res://addons/world_runtime/generation_earthworks.gd")
var road:Dictionary
var view:=SubViewport.new()
var placed:Array[Vector3i]=[]
func _process(_delta:float)->bool:
	if is_instance_valid(game):game.app_focused=true
	return false
func screenshot(label:String,overview:bool=false)->void:
	var center:Vector3=(road.start+road.finish)*.5
	game.camera.global_position=center+Vector3(0,10,17) if overview else center+Vector3(-3,2.1,6.5)
	game.camera.look_at(center+Vector3(0,.4,0))
	game.structures.blocks.flush_bakes()
	for frame in 90:await process_frame
	game.set_process(false);game.shape_preview.hide();game.prefab_preview.hide();game.model_tool.preview.hide()
	check(not game.loading_active and not game.loading_layer.visible,"capture excludes loading overlay")
	await RenderingServer.frame_post_draw
	check(view.get_texture().get_image().save_png(evidence.path_join(label+".png"))==OK,"actual gameplay screenshot "+label)
	game.set_process(true)
func samples()->Dictionary:
	var result:={"rows":[],"within_15cm":0,"over_50cm":0,"mean_gap":0.0,"worst_gap":0.0,"worst_burial":0.0,"burial_total":0.0}
	for across in range(ceili(road.start.x),floori(road.finish.x)):
		for lateral in [-2,0,2]:
			var cell:=Vector3i(across,35,roundi(road.start.z)+lateral)
			var fit:Dictionary=game.structures.blocks.placement_support(AABB(Vector3(cell),Vector3.ONE),Vector3(cell)+Vector3(.5,0,.5),true,true,[game.player.get_rid()],game.prefer_block_burial)
			check(fit.get("ok",false) and fit.get("hits",0)==9,"all nine ground contacts available")
			if not fit.get("ok",false):continue
			result.rows.append({"cell":cell,"support":fit})
			result.within_15cm+=int(fit.gap<=.15);result.over_50cm+=int(fit.gap>.5)
			result.mean_gap+=fit.gap;result.worst_gap=maxf(result.worst_gap,fit.gap)
			result.worst_burial=maxf(result.worst_burial,fit.maximum-fit.bottom)
			result.burial_total+=maxf(0,fit.maximum-fit.bottom)
	result.mean_gap/=maxi(1,result.rows.size())
	return result
func clear_examples()->void:
	for cell:Vector3i in placed:game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,0]))
	placed.clear();game.structures.blocks.flush_bakes()
func place_examples()->void:
	for across in [1007,1011,1015]:
		var point:=Vector3(across+.5,35.5,1093.5)
		game.player.position=point+Vector3(0,0,3)
		game.camera.global_position=point+Vector3(0,1.8,2.8);game.camera.look_at(point-Vector3(0,.5,0))
		var target:Dictionary=game._structure_target(false)
		if not check(target.get("placement_ok",false),"normal click target "+str(across)):continue
		if not check(game.structures.blocks.get_cell(target.target)==0,"comparison does not replace saved construction"):continue
		game._edit_structure(false)
		check(game.structures.blocks.get_cell(target.target)==1,"real click publishes the selected integer-grid brick")
		placed.append(target.target)
		print("BURIAL_BRICK ",target)
	game.structures.blocks.flush_bakes()
	if game.prefer_block_burial and not placed.is_empty():
		var cell:Vector3i=placed[0]
		game.camera.global_position=Vector3(cell)+Vector3(.5,1.4,3)
		game.camera.look_at(Vector3(cell)+Vector3(.5,.85,1))
		var adjacent:Dictionary=game._structure_target(false)
		check(adjacent.get("placement_ok",false) and adjacent.target==cell+Vector3i(0,0,1),"partly buried brick still allows exact adjacent wall placement")
func run()->void:
	var arguments:=PackedStringArray(OS.get_cmdline_user_args())
	if not "--snapshot-readonly" in arguments or not "--temporary" in arguments:quit(2);return
	evidence="res://reports/road_burial_trial/world"
	for argument:String in arguments:
		if argument.begins_with("--burial-evidence="):evidence=argument.trim_prefix("--burial-evidence=")
	DirAccess.make_dir_recursive_absolute(evidence)
	var prepared:Dictionary=FileAccess.open("res://reports/road_burial_trial/selected.bin",FileAccess.READ).get_var()
	road=prepared.road
	view.size=Vector2i(1920,1080);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";view.add_child(game)
	if not check(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,90),"read-only player world loads"):await finish();return
	check(game.terrain.backend.readonly_snapshot and game.terrain.save_slot=="Wild_Hills","original save cannot be written")
	check(not game.prefer_block_burial,"normal gameplay still defaults to original placement")
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.session_menu.set_open(false)
	game.teleport(Vector3(1010,35,1097),36)
	if not check(await wait_for(func():return not game.loading_active and not game.loading_layer.visible and not game.waiting_spawn and game._placement_collision_ready(AABB(Vector3(1002,34,1089),Vector3(19,5,9))),60),"road, collision and landscape loaded"):await finish();return
	game.needs_floor_spawn=false
	if not game.session_menu.developer:game.session_menu.toggle_developer()
	game.player_hud.equip(3);game.structure_shape=1;game.structure_material=0;game.structure_rotation=0;game.structure_prefab_index=-1
	var before:=samples()
	await place_examples();await screenshot("original");clear_examples()
	game.prefer_block_burial=true
	var preferred:=samples()
	await place_examples();await screenshot("prefer_submergence");clear_examples()
	game.player.position=Vector3(1010,36,1101)
	var packets:Array=Earthworks.packets(prepared.trial.segments)
	for index in packets.size():
		var segment:Dictionary=prepared.trial.segments[index]
		if not check(game.terrain.edit(packets[index],segment.start.min(segment.finish),segment.start.max(segment.finish)),"in-memory generation road stamp "+str(index)):await finish();return
		if not check(await wait_for(func():return not game.terrain.pending_edit,15),"road stamp settled"):await finish();return
	if not check(await wait_for(func():return game._placement_collision_ready(AABB(Vector3(1002,34,1089),Vector3(19,5,9))),45),"corrected surface collision ready"):await finish();return
	for frame in 30:await process_frame
	var corrected:=samples()
	await place_examples();await screenshot("gentle_correction");await screenshot("gentle_overview",true);clear_examples()
	check(preferred.worst_gap<before.worst_gap and preferred.mean_gap<before.mean_gap,"submergence preference reduces typical and worst floating gaps")
	check(corrected.burial_total<preferred.burial_total and corrected.worst_gap<=preferred.worst_gap+.025,"gradual road correction reduces aggregate burial without trading for a large gap")
	check(corrected.worst_burial<=.601,"at least forty centimetres of a buried cube remains visible")
	var floating:=Vector3i(1010,42,1093)
	game.structures.blocks.set_cells(PackedInt32Array([floating.x,floating.y,floating.z,1]));game.structures.blocks.flush_bakes()
	await wait_for(func():return game._placement_collision_ready(AABB(Vector3(floating),Vector3.ONE*2)),10)
	game.camera.global_position=Vector3(floating)+Vector3(.5,.5,3);game.camera.look_at(Vector3(floating)+Vector3.ONE*.5)
	var aerial:Dictionary=game._structure_target(false)
	check(aerial.get("placement_ok",false) and aerial.target==floating+Vector3i(0,0,1),"floating face adjacency remains exact")
	FileAccess.open(evidence.path_join("contact.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"road":road,"before":before,"preferred":preferred,"corrected":corrected,"scope":"Read-only Wild_Hills snapshot; temporary road grading is not saved. No supports, placement terrain edits or grid offsets."},"  "))
	await finish()
func finish()->void:
	if is_instance_valid(game):
		game.shutdown_requested=true
		check(await game.terrain.shutdown_after_edits(),"read-only preview closes without saving")
		game.free();await process_frame
	print("ROAD_BURIAL_WORLD_PREVIEW failures=",failures)
	quit(1 if failures else 0)
