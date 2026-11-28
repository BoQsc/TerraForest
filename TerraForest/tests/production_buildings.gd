# SPDX-License-Identifier: 0BSD
extends "res://tests/civic_world.gd"
const LakeCodec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const E2=preload("res://addons/structures/expansion_catalog.gd")
var metropolis:=false
var inhabited_island:=false
var capture_prefix:=""

func _physics_process(delta:float)->bool:
	# Camera/capsule inspection suspends the player controller, not streaming.
	# Keep the normal NPC residency owner running while those helpers await
	# collision at another location; otherwise old bodies fall through unloaded
	# terrain while their parent world's physics callback is suspended.
	if metropolis and is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn" and current_scene.startup_complete and not current_scene.is_physics_processing():
		var game:Node=current_scene
		game.terrain.focus=game.player.global_position
		game.zombies.update(delta,game.player.global_position,false,false)
		game.actors.update_simulation(delta,game.terrain.focus,false,game._actor_collision_ready)
	return false

func run()->void:
	metropolis="--metropolis" in OS.get_cmdline_user_args()
	inhabited_island="--inhabited-island" in OS.get_cmdline_user_args()
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--metropolis-capture-prefix="):capture_prefix=argument.trim_prefix("--metropolis-capture-prefix=")
	if not capture_prefix.is_empty() and not capture_prefix.is_valid_identifier():quit(2);return
	folder="res://reports/production_buildings"
	if metropolis:
		for argument:String in OS.get_cmdline_user_args():
			if argument.begins_with("--metropolis-evidence="):folder=argument.trim_prefix("--metropolis-evidence=")
		if not folder.is_absolute_path() or not folder.contains("/reports/inhabited_island_world/" if inhabited_island else "/reports/metropolis_world/"):push_error("Use the admitted metropolis launcher");quit(2);return
	DirAccess.make_dir_recursive_absolute(folder)
	restoration="--restore-production" in OS.get_cmdline_user_args()
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed
	await wait_for(browser_catalog_ready)
	var browser=current_scene
	if "--create-production" in OS.get_cmdline_user_args():
		selected_slot=("Island_1703_" if inhabited_island else "Metropolis_1703_" if metropolis else "CivicTown_1703_")+Crypto.new().generate_random_bytes(4).hex_encode()
		browser.name_field.text=selected_slot;browser.seed_field.value=1703;browser.world_tabs.current_tab=1
		if metropolis:preload("res://demo/world_creation_panel.gd").apply_style(browser,7 if inhabited_island else 6)
		check(browser.world_style.get_item_text(browser.world_style.selected)==("Inhabited island · living shores" if inhabited_island else "Metropolis & inhabited region" if metropolis else "Connected countryside"),"normal selected recipe has its public UI identity")
		check(browser.selected_options()==(Recipe.INHABITED_ISLAND if inhabited_island else Recipe.METROPOLIS if metropolis else Recipe.DEFAULTS),"unchanged normal UI settings reach generation")
		await photograph("create_world")
		var generation_clicked:=Time.get_ticks_usec()
		browser.generate_button.pressed.emit()
		var status_path:String=browser.preparation_status
		if metropolis:
			var request:=FileAccess.open(folder.path_join("request.json"),FileAccess.WRITE)
			request.store_string(JSON.stringify({"slot":selected_slot,"status":status_path,"pid":OS.get_process_id()}));request.close()
		await wait_for(func():
			if game_ready():return true
			if browser_ready() and current_scene.preparation_pid<0 and FileAccess.file_exists(status_path):
				var state=JSON.parse_string(FileAccess.get_file_as_string(status_path))
				return state is Dictionary and state.get("state","") in ["failed","cancelled"]
			return false,520)
		if not check(game_ready(),"normal Generate & play creates and opens the civic world"):
			print("PRODUCTION_GENERATION_STATUS ",FileAccess.get_file_as_string(status_path));await finish();return
		var generate_to_play_us:=Time.get_ticks_usec()-generation_clicked
		var atlas:Node=current_scene.world_map
		var map_reuse:Dictionary={"terrain":{"cache_hits":atlas.updates.cache_hits,"patches":atlas.updates.patches,"cache_writes":atlas.updates.cache_writes}}
		for overlay:Node in [atlas.water_survey,atlas.block_survey,atlas.model_survey]:
			map_reuse[overlay.caption]={"cache_hits":overlay.cache_hits,"fast_cache_hits":overlay.fast_cache_hits,"cache_writes":overlay.cache_writes,"builds":overlay.builds,"source_calls":overlay.source_calls,"visibility_calls":overlay.visibility_calls}
		FileAccess.open(folder.path_join("first_play_map_reuse.json"),FileAccess.WRITE).store_string(JSON.stringify(map_reuse,"  "))
		if inhabited_island:check(map_reuse.Water.fast_cache_hits==1 and map_reuse.Water.source_calls==0 and map_reuse.Water.visibility_calls==0,"first play reuses the certified water map without rebuilding")
		check(current_scene.ground_enabled and current_scene.ground_cover.is_processing(),"ordinary Generate-to-play keeps ground vegetation enabled")
		var state:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(status_path))
		var receipt:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(state.report).path_join("run.json")))
		var plan_identity:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(state.report).path_join("generation_plan_identity.json")))
		FileAccess.open(folder.path_join("generate_to_play.json"),FileAccess.WRITE).store_string(JSON.stringify({"microseconds":generate_to_play_us,"plan_cache_hit":plan_identity.get("cache_hit",null),"loading_stages":current_scene.loading_diagnostics.stages,"target_microseconds":30000000,"performance_passed":generate_to_play_us<30000000,"first_play_startup_ms":current_scene.startup_timings,"first_play_session":root.get_node("WorldSession").stage_timings,"loading_us":Time.get_ticks_usec()-current_scene.loading_started_us,"scope":"Generate button through playable-world readiness, including planning, all generation, durable publication and first world load."}))
		var ordinary:=true
		for phase:Dictionary in receipt.phases:
			for argument:String in phase.arguments:ordinary=ordinary and argument not in ["--civic-review","--building-expansion-review","--review-generation"]
		check(ordinary,"production generation uses no review-only flags")
		var identity:Dictionary={"slot":selected_slot,"status":status_path,"report":state.report}
		FileAccess.open(folder.path_join("slot.json"),FileAccess.WRITE).store_string(JSON.stringify(identity))
		if metropolis:identity["created"]=true;FileAccess.open(folder.path_join("world.json"),FileAccess.WRITE).store_string(JSON.stringify(identity))
		check(current_scene.generated_region.store.get_plan().places.any(func(place:Dictionary):return int(place.id)==Civic.MERCHANT_PLACE),"normal generated world persists resident trader location")
		await photograph("first_play")
		await finish();return
	var saved=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("slot.json")))
	if not check(saved is Dictionary and str(saved.get("slot","")).begins_with("Island_1703_" if inhabited_island else "Metropolis_1703_" if metropolis else "CivicTown_1703_"),"integration owns its new world only"):await finish();return
	selected_slot=saved.slot
	var selected:=-1
	for index in browser.worlds.item_count:
		if browser.worlds.get_item_metadata(index)==selected_slot:selected=index;break
	if not check(selected>=0,"normal saved-world browser lists the generated world"):await finish();return
	browser.worlds.select(selected);browser.launch_selected(false)
	if not check(await wait_for(game_ready,120),"normal Open selected world restores in a fresh process"):await finish();return
	var game=current_scene;game.background_fps=60;game.app_focused=true
	check(not Options.arguments().has("--civic-review") and not Options.arguments().has("--building-expansion-review"),"ordinary saved-world session needs no review switches")
	var settings:Dictionary=Recipe.codec().decode(game.world_recipe.store.capture_snapshot())
	var worker:=Thread.new();worker.start(Plan.build.bind(1703,game.terrain.backend.world_generator,true,true,"user://generation_plans",settings))
	while worker.is_alive():await process_frame
	planned=worker.wait_to_finish()
	if not check(planned.get("ok",false),"normal recipe reconstructs the generated plan"):await finish();return
	check(planned.cache_hit and planned.sites[0].recipe_kind==("metropolis" if metropolis else "civic"),"preview and generation reuse the same approved civic plan")
	var markers:Array=game.generated_region.store.get_plan().places.filter(func(place:Dictionary):return int(place.id)==Civic.MERCHANT_PLACE)
	check(markers.size()==1,"exactly one resident trader map destination persists")
	var available:={}
	for asset:Resource in game.structure_prefabs:
		if asset.has_meta("expansion_id"):available[str(asset.get_meta("expansion_id"))]=true
	check(available.size()==9,"all nine approved E2 buildings are in normal construction")
	for site:Dictionary in planned.sites:
		for lot:Dictionary in site.lots:
			if not lot.asset.has_meta("expansion_id"):continue
			var id:String=lot.asset.get_meta("expansion_id")
			if approved_records.has(id):continue
			var transformed:Resource=ClassDB.instantiate("NativeBlockPrefab")
			transformed.compose([lot.asset],PackedInt32Array([0,lot.origin.x,lot.origin.y,lot.origin.z,lot.rotation]))
			approved_records[id]=transformed.get_records();approved_lots[id]=lot
	check(approved_records.size()==(9 if metropolis else 8),"default civic and market plan includes all five civic and three small-building E2 types")
	if not restoration:await verify_approved_records(game)
	var trader_lots:Array=planned.sites[0].lots.filter(func(lot:Dictionary):return lot.asset.has_meta("trader_anchor"))
	if check(trader_lots.size()==1,"exactly one trader building is identifiable"):await trade_world(game,trader_lots[0])
	if metropolis:await inspect_lakes(game)
	if not restoration:
		for lot:Dictionary in planned.sites[0].lots:
			if lot.asset.has_meta("civic_id"):await inspect_detail(game,lot)
		if metropolis:await inspect_metropolis(game)
	FileAccess.open(folder.path_join("restore.json" if restoration else "result.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":selected_slot,"checks":checks,"failures":failures,"generation":"normal UI, no review flags","recipe":settings,"plan_digest":planned.plan_digest}))
	await finish()

func inspect_lakes(game:Node)->void:
	if inhabited_island:
		var habitat:PackedByteArray=game.ecosystem._scatter().capture_storage_snapshot()
		check(habitat.size()>4624 and habitat.decode_u32(0)==0x32565247,"ordinary world restores native shoreline habitat")
		if restoration:check(habitat==FileAccess.get_file_as_bytes(folder.path_join("expected_shore_habitat.bin")),"shoreline guide bytes survive durable save and fresh-process reload")
		else:FileAccess.open(folder.path_join("expected_shore_habitat.bin"),FileAccess.WRITE).store_buffer(habitat)
	var lake_core=ClassDB.instantiate("TerrainCore");lake_core.execute(LakeCodec.command(6,[1703,game.terrain.backend.world_generator]))
	var definitions:Dictionary=preload("res://addons/volumetric_terrain/generated_lakes.gd").describe(lake_core,game.terrain.backend.world_generator)
	var audit:Dictionary=planned.get("lake_audit",{})
	check(game.terrain.backend.world_generator==(38 if inhabited_island else 33) and int(audit.get("extensive_count",0))>=3,"normal UI publishes the coast profile with three audited long lakes")
	for index in mini(3,audit.get("lakes",[]).size()):
		var lake:Dictionary=audit.lakes[index];var center:Vector3=lake.center
		# A branching/crescent lake can have dry land at its geometric center.
		# Choose the nearest physical catalog source, never invent a wet point.
		var nearest:=INF;var source:=center;var selected:Dictionary={}
		for section:Dictionary in definitions.records:
			if absf(section.level-center.y)>.001:continue
			var candidate:Vector3=Vector3(section.seed.x,section.level,section.seed.z)
			var distance:=candidate.distance_squared_to(center)
			if distance<nearest:nearest=distance;source=candidate;selected=section
		# Equal water elevations do not identify a lake. Join only adjacent
		# physical catalog sections around the selected source.
		var lake_bounds:=AABB(selected.origin,Vector3(selected.cells)*selected.spacing)
		var joined:Array=[selected.id]
		for pass_index in definitions.records.size():
			for section:Dictionary in definitions.records:
				if section.id in joined or absf(section.level-center.y)>.001:continue
				var bounds:=AABB(section.origin,Vector3(section.cells)*section.spacing)
				if lake_bounds.grow(.01).intersects(bounds):lake_bounds=lake_bounds.merge(bounds);joined.append(section.id)
		center=source
		game.teleport(center+Vector3(0,5,0),center.y+5);game.set_physics_process(false);game._clear_motion();game.fly=true
		game.camera.cull_mask&=~((1<<18)|(1<<19))
		game.camera.global_position=center+Vector3(6,5,6);game.camera.look_at(center)
		check(await wait_for(func():return not game.loading_active and game.lakes.water.depth_at(center-Vector3(0,.5,0))>.1,90),"restored real water fills long lake "+str(index))
		var owner:=Vector3i(((center-Vector3.UP*.0001)/4).floor())
		check(await wait_for(func():return game.lakes._meshes.has(owner),90),"actual water render geometry reaches long lake "+str(index))
		if inhabited_island and not restoration:
			var across:=Vector3.BACK if lake_bounds.size.x>lake_bounds.size.z else Vector3.RIGHT
			var probes:=PackedVector3Array()
			for step in 70:probes.append(center+across*float(step*2))
			var heights:PackedFloat32Array=ClassDB.instantiate("NativeGenerationEarthworks").heights(game.terrain.backend.native,probes)
			var bank:=-1
			for step in heights.size()-3:
				if heights[step]>center.y+.2:bank=step+2;break
			if check(bank>=0,"actual dry shore found for lake "+str(index)):
				var eye:Vector3=probes[bank];eye.y=heights[bank]+1.7
				game.teleport(eye,eye.y);game.set_physics_process(false);game._clear_motion();game.fly=true
				check(await wait_for(func():return not game.loading_active,90),"refined lake shore landscape resident")
				game.camera.global_position=eye;game.camera.look_at(center+Vector3.UP*.4)
				await settle_lake_view(game,index,"shore")
				await photograph("island_lake_"+str(index)+"_shore")
				game.camera.global_position=center+Vector3(170,160,170);game.camera.look_at(center)
				if index==2:
					for frame in 45:await process_frame
					await photograph("island_lake_2_before_view_residency")
				await settle_lake_view(game,index,"overview")
				await photograph("island_lake_"+str(index)+"_overview")
		if index==0 and not restoration and not inhabited_island:
			var along:=Vector3.RIGHT if lake_bounds.size.x>lake_bounds.size.z else Vector3.BACK
			var across:=Vector3.BACK if lake_bounds.size.x>lake_bounds.size.z else Vector3.RIGHT
			var low_view:Vector3=center-along*(float(lake.length_m)*.35)+Vector3.UP*3
			game.teleport(low_view,low_view.y);game.set_physics_process(false);game._clear_motion();game.fly=true
			await wait_for(func():return not game.loading_active,90)
			game.camera.global_position=low_view;game.camera.look_at(center+along*float(lake.length_m)*.3)
			for frame in 90:await process_frame
			var view:Dictionary={"player":str(game.player.global_position),"focus":str(game.terrain.focus),"camera":str(game.camera.global_position),"render_pages":game.lakes.statistics().render_pages,"native":game.lakes.water.runtime_state()}
			FileAccess.open(folder.path_join("lake_view.json"),FileAccess.WRITE).store_string(JSON.stringify(view,"  "))
			await photograph("long_lake_generated_shore")
			game.camera.global_position=center+Vector3(240,220,240);game.camera.look_at(center)
			for frame in 45:await process_frame
			await photograph("long_lake_generated_overview")
	game.terrain.render_view=Vector3.INF
	game.set_physics_process(true)

func settle_lake_view(game:Node,index:int,kind:String)->void:
	# Match the ordinary overview controller: detached review cameras must tell
	# the native planner where they are, then wait for completed geometry.
	game.terrain.render_view=game.camera.global_position
	game.terrain.render_projection_scale=clampf(float(root.size.y)/1080.0*tan(deg_to_rad(75.0)*.5)/tan(deg_to_rad(game.camera.fov)*.5),.25,2.0)
	game.terrain.schedule_timer=-1.0
	for frame in 3:await process_frame
	check(await wait_for(func():
		var water:Dictionary=game.lakes.water.runtime_state()
		return game.terrain.backend.queued()==0 and game.terrain.in_flight.is_empty() and game.terrain.staging.is_empty() and game.terrain.preparation.is_empty() and water.dirty_meshes==0 and not water.mesh_batch_active and not water.mesh_publish_pending,90),"lake "+str(index)+" "+kind+" render work completed")
	var evidence:Dictionary={"camera":str(game.camera.global_position),"focus":str(game.terrain.focus),"render_view":str(game.terrain.render_view),"projection_scale":game.terrain.render_projection_scale,"terrain":game.terrain.loading_state(game.player.global_position,true),"visible_cut":game.terrain.visible_cut.size(),"water":game.lakes.water.runtime_state(),"vegetation_enabled":game.ground_enabled}
	var species:Array=[]
	for batch:Node in game.ground_cover.batches:species.append(batch.get_ids().size())
	evidence["species_counts"]=species
	if kind=="shore":check(game.ground_enabled and species.size()>=9 and species[2]>0,"lake "+str(index)+" has enabled and populated natural grass")
	FileAccess.open(folder.path_join("lake_%d_%s_view.json"%[index,kind]),FileAccess.WRITE).store_string(JSON.stringify(evidence,"  "))

func inspect_metropolis(game:Node)->void:
	var landmarks:=0
	for site:Dictionary in planned.sites:
		for lot:Dictionary in site.lots:
			if not lot.asset.has_meta("grand_building_id"):continue
			landmarks+=1
			var id:String=lot.asset.get_meta("grand_building_id")
			var bounds:AABB=lot.asset.placement_bounds(lot.origin,lot.rotation)
			game.teleport(lot.entrance.segment.finish+Vector3.UP)
			var local_bounds:=AABB(lot.entrance.segment.finish-Vector3(3,1,3),Vector3(6,4,6))
			if not check(await wait_for(func():return not game.loading_active and game.structures.is_collision_region_ready(local_bounds),90),id+" local entrance collision and landscape resident"):continue
			var transformed:Resource=ClassDB.instantiate("NativeBlockPrefab")
			transformed.compose([lot.asset],PackedInt32Array([0,lot.origin.x,lot.origin.y,lot.origin.z,lot.rotation]))
			var cells:PackedInt32Array=transformed.get_records();var exact:=true
			for at in range(0,cells.size(),4):
				if game.structures.blocks.get_cell(Vector3i(cells[at],cells[at+1],cells[at+2]))!=cells[at+3]:exact=false;break
			check(exact,id+" every authored and footing cell survives normal save/reopen")
			game.set_physics_process(false);game._clear_motion();game.fly=true
			game.camera.cull_mask&=~((1<<18)|(1<<19))
			game.camera.global_position=lot.entrance.segment.finish+Vector3(4,1.7,2)
			game.camera.look_at(bounds.get_center())
			for frame in 45:await process_frame
			await photograph(id+"_generated_street")
			game.camera.global_position=bounds.get_center()+Vector3(bounds.size.x*.8,bounds.size.y*.65,bounds.size.z*.85)
			game.camera.look_at(bounds.get_center())
			for frame in 30:await process_frame
			await photograph(id+"_generated_overview")
			if id=="grand_cathedral":
				game.player.position=point(lot,Vector3(50,1.05,20))
				game.camera.global_position=point(lot,Vector3(50,2.7,20));game.camera.look_at(point(lot,Vector3(50,2.7,60)))
				for frame in 45:await process_frame
				await photograph("grand_cathedral_generated_crypt")
	check(landmarks==3,"all three grand buildings are present in the ordinary generated city")
	for index in planned.bridges.size():
		var crossing:Dictionary=planned.bridges[index]
		var middle:Vector3=(crossing.banks[0]+crossing.banks[1])*.5
		game.teleport(middle+Vector3.UP)
		if not check(await wait_for(func():return not game.loading_active,90),"bridge "+str(index)+" generated landscape resident"):continue
		game.set_physics_process(false);game._clear_motion();game.fly=true
		game.camera.global_position=middle+Vector3(24,18,20);game.camera.look_at(middle)
		for frame in 45:await process_frame
		await photograph("metropolis_bridge_"+str(index))
	game.set_physics_process(true)

func photograph(name:String)->void:
	var destination:String=folder if capture_prefix.is_empty() else folder.path_join(capture_prefix)
	DirAccess.make_dir_recursive_absolute(destination)
	await RenderingServer.frame_post_draw
	if "--no-captures" in OS.get_cmdline_user_args():return
	if "--lake-captures-only" in OS.get_cmdline_user_args() and name!="first_play" and not name.begins_with("island_lake_"):return
	root.get_texture().get_image().save_png(destination.path_join(name+".png"))

func finish()->void:
	if is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn":
		current_scene.trader.ui.close();current_scene.shutdown_requested=true
		check(await current_scene.terrain.shutdown_after_edits(),"normal generated world durably saves after interaction")
	if is_instance_valid(current_scene):current_scene.free()
	# Let deferred native reference releases and the awaiting run() unwind before
	# engine teardown; immediate quit can leave a zero-reference object queued.
	await RenderingServer.frame_post_draw
	for frame in 8:await process_frame
	print("PRODUCTION_BUILDINGS checks=",checks," failures=",failures," slot=",selected_slot)
	_quit_after_finish.call_deferred(1 if failures else 0)

func _quit_after_finish(code:int)->void:
	# Resume on a fresh frame after run()/finish() have released their locals.
	await process_frame
	quit(code)
