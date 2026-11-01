# SPDX-License-Identifier: 0BSD
extends "res://tests/civic_world.gd"
const Expansion=preload("res://reviews/building_expansion/recipes.gd")
var expansion_after:=false
var review_lots:Array=[]
var house_only:=false
var persist_review:=false
var reopen_review:=false
var views:=[]
func run()->void:
	house_only="--expansion-house-only" in OS.get_cmdline_user_args()
	persist_review="--expansion-save" in OS.get_cmdline_user_args();reopen_review="--expansion-reopen" in OS.get_cmdline_user_args()
	if "--build-house-baseline" in OS.get_cmdline_user_args():await build_house_baseline();return
	expansion_after="--expansion-after" in OS.get_cmdline_user_args()
	var phase:=("house_" if house_only else "")+("E2" if expansion_after or reopen_review else "R1")+("_restore" if reopen_review else "")
	folder="res://reports/building_expansion/"+phase+"_"+str(Time.get_unix_time_from_system()).replace(".","_")
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open("res://reports/building_expansion/latest_"+phase+".json",FileAccess.WRITE).store_string(JSON.stringify({"folder":folder}))
	selected_slot=JSON.parse_string(FileAccess.get_file_as_string("res://reports/building_expansion/house_slot.json" if house_only else "res://reports/civic_world/slot.json")).slot
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--expansion-slot="):
			selected_slot=arg.trim_prefix("--expansion-slot=")
			if not check(selected_slot.begins_with("Expansion_") and selected_slot.is_valid_filename(),"persistent test restricted to an owned expansion clone"):await finish();return
	var path:="user://worlds/"+selected_slot+".trw";var before:=FileAccess.get_sha256(path)
	var arguments:=PackedStringArray(["--world-slot="+selected_slot,"--gameplay-construction","--ground-cover","--actors","--vehicle-fleet","--no-zombies"])
	if not persist_review:arguments.append("--snapshot-readonly")
	Options.set_arguments(arguments,true)
	change_scene_to_file("res://demo/world.tscn");await scene_changed
	if not check(await wait_for(game_ready,120),"matched populated civic baseline opens read-only"):await finish();return
	var game=current_scene;game.background_fps=60;game.app_focused=true
	var original_camera:Transform3D=game.camera.transform
	var worker:=Thread.new();worker.start(Plan.build.bind(1703,29,true,true,"user://expansion_review_plans",Recipe.DEFAULTS,null,not house_only))
	while worker.is_alive():await process_frame
	planned=worker.wait_to_finish()
	if not check(planned.get("ok",false),"same seed and lot plan"):await finish();return
	review_lots=planned.sites[0].lots.duplicate() if not house_only else []
	if house_only:
		var original_house:Resource=load("res://addons/structures/prefabs/large_house_c1.tres")
		for house:Dictionary in planned.sites[0].lots:
			if house.asset.get_records()==original_house.get_records():
				house=house.duplicate();house.asset=house.asset.duplicate();house.asset.set_meta("civic_id","house_c1");review_lots.append(house);break
		check(review_lots.size()==1,"approved large house identified in populated northern district")
	var found:={}
	for site:Dictionary in ([] if house_only else planned.sites.slice(1)):
		for lot:Dictionary in site.lots:
			for family_index in range(5,8):
				var source:Resource=load("res://addons/structures/prefabs/"+Expansion.SOURCES[family_index]+".tres")
				if not found.has(family_index) and lot.asset.get_records()==source.get_records():
					lot=lot.duplicate();lot.asset=lot.asset.duplicate();lot.asset.set_meta("civic_id",Expansion.IDS[family_index]);review_lots.append(lot);found[family_index]=true
	check(house_only or found.size()==3,"existing cottage and both shop designs identified in the populated market")
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--expansion-only="):review_lots=review_lots.filter(func(lot:Dictionary):return lot.asset.get_meta("civic_id")==argument.trim_prefix("--expansion-only="))
	for index in review_lots.size():
		var lot:Dictionary=review_lots[index]
		var id:String=lot.asset.get_meta("civic_id")
		if not lot.asset.has_meta("site_entrance"):
			# Older resources have an authored front-door attachment but no route
			# metadata. Fixture coordinates below match those retained doors.
			var local_entry:Vector3={"cottage_a2":Vector3(.5,2,6.5),"shop_b1":Vector3(.5,1,9.5),"shop_b2":Vector3(.5,1,9.5),"house_c1":Vector3(.5,5,8.5)}[id]
			lot.asset.set_meta("site_entrance",local_entry)
			lot.asset.set_meta("site_access_goal",local_entry+Vector3(0,.04,-2.2))
			if id=="house_c1":
				lot.asset.set_meta("stair_routes",[{"kind":"stairs","start":Vector3(2.5,1.02,-5.2),"end":Vector3(2.5,5.02,.8)},{"kind":"stairs","start":Vector3(2.5,5.02,-5.2),"end":Vector3(2.5,9.02,.8)}])
		game.teleport(lot.entrance.segment.finish+Vector3.UP)
		var bounds:AABB=lot.asset.placement_bounds(lot.origin,lot.rotation)
		if not check(await wait_for(func():return not game.loading_active and game.world_vehicle.ready_bounds(game,bounds.grow(3).expand(lot.entrance.segment.finish)),90),id+" full collision ready"):continue
		var candidate:Resource=load("res://addons/structures/prefabs/expansion_"+id+"_e2.tres")
		check(candidate.get_model_attachments()==lot.asset.get_model_attachments(),id+" furnishings, windows and doors remain identical")
		if expansion_after or reopen_review:
			var authored:Resource=ClassDB.instantiate("NativeBlockPrefab");authored.compose([lot.asset],PackedInt32Array([0,lot.origin.x,lot.origin.y,lot.origin.z,lot.rotation]))
			var replaced:Resource=ClassDB.instantiate("NativeBlockPrefab");replaced.compose([candidate],PackedInt32Array([0,lot.origin.x,lot.origin.y,lot.origin.z,lot.rotation]))
			var changes:={};var old:PackedInt32Array=authored.get_records();var fresh:PackedInt32Array=replaced.get_records();var exact:=true
			for offset in range(0,old.size(),4):
				var cell:=Vector3i(old[offset],old[offset+1],old[offset+2]);exact=exact and game.structures.blocks.get_cell(cell)==old[offset+3];changes[cell]=0
			for offset in range(0,fresh.size(),4):changes[Vector3i(fresh[offset],fresh[offset+1],fresh[offset+2])]=fresh[offset+3]
			if reopen_review:
				var restored_ok:=true
				for cell:Vector3i in changes:restored_ok=restored_ok and game.structures.blocks.get_cell(cell)==changes[cell]
				check(restored_ok,id+" exact expansion cells and removed baseline cells survive fresh process")
				continue
			if not check(exact,id+" approved baseline exact before reversible replacement"):continue
			var records:=PackedInt32Array()
			for cell:Vector3i in changes:records.append_array(PackedInt32Array([cell.x,cell.y,cell.z,changes[cell]]))
			var started:=Time.get_ticks_usec()
			check(game.structures.blocks.set_cells(records),id+" native atomic revision publication")
			if not check(await wait_for(func():return game.structures.is_collision_region_ready(bounds.grow(2)),90),id+" new geometry collision ready"):continue
			metrics.append({"id":id,"publication_ms":(Time.get_ticks_usec()-started)/1000.0})
			game.terrain.changed_since_save=true
		if "--expansion-quick" in OS.get_cmdline_user_args():continue
		if "--expansion-damage-only" in OS.get_cmdline_user_args():
			game.set_physics_process(false);await inspect_local_removal(game,lot,candidate);game.set_physics_process(true);continue
		game.set_physics_process(false);game._clear_motion();game.fly=true
		game.player.position=lot.entrance.segment.finish+Vector3.UP
		game.camera.cull_mask&=~((1<<18)|(1<<19))
		for frame in 120:await process_frame
		var entrance:Vector3=point(lot,lot.asset.get_meta("site_entrance"))
		var center:Vector3=bounds.get_center()
		var cameras:=[
			["street",lot.entrance.segment.finish+Vector3(10,1.65,8),entrance+Vector3.UP*2],
			["overview",center+Vector3(38,24,48),center],
			["roof_join",center+Vector3(14,12,18),center+Vector3.UP*4],
			["inside",point(lot,lot.asset.get_meta("site_entrance")+Vector3(0,1.65,-2)),point(lot,lot.asset.get_meta("site_entrance")+Vector3(0,1.65,-8))]]
		if id=="school_s2":cameras.append(["underside",point(lot,Vector3(5.5,10.2,20)),point(lot,Vector3(5.5,12.5,24))])
		if id=="house_c1":cameras.append(["basement",point(lot,Vector3(.5,2.65,4.5)),point(lot,Vector3(2.5,2,-4))])
		elif lot.asset.has_meta("cellar_clearance"):cameras.append(["basement",point(lot,Vector3(7,2.7,10)),point(lot,Vector3(3,2,5))])
		for view:Array in cameras:
			game.camera.global_position=view[1];game.camera.look_at(view[2])
			for frame in 20:await process_frame
			await photograph(id+"_"+view[0]);views.append({"id":id,"view":view[0],"position":view[1],"target":view[2]})
		await profile_lot(game,lot,id)
		if expansion_after and id in ["trader_t1","town_hall_t1"]:await inspect_material_size(game,lot,id)
		if expansion_after and id=="town_hall_t1":await inspect_local_removal(game,lot,candidate)
		if "--expansion-routes" in OS.get_cmdline_user_args():
			game.camera.transform=original_camera;game.set_physics_process(true)
			var matched_folder:=folder;folder=matched_folder.path_join("routes");DirAccess.make_dir_recursive_absolute(folder)
			await inspect_civic(game,lot);await inspect_detail(game,lot)
			folder=matched_folder
		game.camera.transform=original_camera
		game.set_physics_process(true)
	if "--expansion-travel" in OS.get_cmdline_user_args():await inspect_player_travel(game,original_camera)
	check(before==FileAccess.get_sha256(path),"approved save remains byte-identical")
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"phase":phase,"slot":selected_slot,"candidates":JSON.parse_string(FileAccess.get_file_as_string("res://reviews/building_expansion/provenance.json")),"native_sha256":FileAccess.get_sha256("res://addons/structures/bin/structures.windows.template_debug.x86_64.dll"),"metrics":metrics,"views":views,"gpu":RenderingServer.get_video_adapter_name(),"resolution":root.size,"routes":"--expansion-routes" in OS.get_cmdline_user_args()},"  "))
	await finish()

func inspect_player_travel(game:Node,camera_pose:Transform3D)->void:
	var site:Dictionary=planned.sites[0];var hall:Dictionary=site.lots[1]
	var target:Vector3=hall.asset.placement_bounds(hall.origin,hall.rotation).get_center()
	var start:Vector3=site.center+Vector3(-64,0,64)
	var stops:Array[Vector3]=[site.center+Vector3(-64,0,-64),hall.entrance.segment.finish]
	game.camera.transform=camera_pose;game.fly=false;game.set_physics_process(true);game.teleport(start)
	if not check(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,90),"actual player travel starts on surveyed civic street"):return
	game.set_physics_process(false);game._clear_motion();game.terrain.require_collision=true
	var travelled:=0.0;var holds:=0;var falling:=false
	game.camera.look_at(target)
	for frame in 60:await process_frame
	await photograph("player_travel_far")
	views.append({"id":"travel","view":"far","position":game.camera.global_position,"target":target})
	metrics.append({"id":"travel_far","distance":game.player.position.distance_to(target),"lod":game.structures.blocks.geometry_lod_stats()})
	for index in stops.size():
		var goal:Vector3=stops[index];var arrived:=false;var held_ticks:=0
		for tick in 2400:
			await physics_frame;game.app_focused=true
			game.terrain.focus=game.player.position
			var offset:Vector3=goal-game.player.position;offset.y=0
			if offset.length()<.18:arrived=true;break
			var direction:=offset.normalized()
			var envelope:=AABB(game.player.position-Vector3(.6,.2,.6),Vector3(1.2,2.2,1.2)).expand(game.player.position+direction*.35).grow(.1)
			if not game.world_vehicle.ready_bounds(game,envelope):
				holds+=1;held_ticks+=1;game.player.velocity=Vector3.ZERO
				if held_ticks>300:break
				continue
			held_ticks=0
			var before:Vector3=game.player.position
			game.player.velocity=game.movement.walking_velocity(direction,game.player.velocity,1.0/60,false,game.player.is_on_floor(),false)
			game.movement.move_grounded(game.player,1.0/60)
			travelled+=Vector2(before.x-game.player.position.x,before.z-game.player.position.z).length()
			falling=falling or game.player.velocity.y < -10
			game.camera.look_at(target)
		check(arrived,"actual player continuously walks surveyed street leg "+str(index)+" position="+str(game.player.position))
		if not arrived:break
		for frame in 60:await process_frame
		var view:="mid" if index==0 else "near"
		await photograph("player_travel_"+view)
		views.append({"id":"travel","view":view,"position":game.camera.global_position,"target":target})
		metrics.append({"id":"travel_"+view,"distance":game.player.position.distance_to(target),"lod":game.structures.blocks.geometry_lod_stats()})
	check(travelled>180 and not falling,"over 180 m of supported actual-player travel with no teleport after start or unsupported fall")
	metrics.append({"id":"player_travel","metres":travelled,"collision_hold_ticks":holds,"unsupported_fall":falling})
	game.camera.transform=camera_pose;game.set_physics_process(true)

func profile_lot(game:Node,lot:Dictionary,id:String)->void:
	var viewport:=root.get_viewport_rid();RenderingServer.viewport_set_measure_render_time(viewport,true)
	var bounds:AABB=lot.asset.placement_bounds(lot.origin,lot.rotation);var target:=bounds.get_center()
	game.camera.global_position=target+Vector3(38,24,48);game.camera.look_at(target)
	for frame in 90:await process_frame
	var intervals:=[];var gpu:=[];var cpu:=[];var previous:=Time.get_ticks_usec()
	for frame in 360:
		game.camera.global_position=target+Vector3(38,24,48)*(1.0-float(frame)/720.0);game.camera.look_at(target)
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec();intervals.append((now-previous)/1000.0);previous=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport));cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport))
	intervals.sort();gpu.sort();cpu.sort()
	metrics.append({"id":id,"frame_p95_ms":intervals[342],"frame_worst_ms":intervals[-1],"cpu_p95_ms":cpu[342],"gpu_p95_ms":gpu[342],"fps_cap":Engine.max_fps,"texture_memory":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"video_memory":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"blocks":game.structures.blocks.stats(),"lod":game.structures.blocks.geometry_lod_stats()})
	for distance:float in [30,75,150]:
		game.camera.global_position=target+Vector3(.5,.25,1).normalized()*distance;game.camera.look_at(target)
		for frame in 60:await process_frame
		await photograph(id+"_distance_"+str(int(distance)))

func finish()->void:
	print("BUILDING_EXPANSION_WORLD checks=",checks," failures=",failures," folder=",folder)
	await super.finish()

func inspect_material_size(game:Node,lot:Dictionary,id:String)->void:
	var material:ShaderMaterial
	for child in game.structures.blocks.get_children():
		if child is MeshInstance3D:material=child.get_active_material(0);break
	if not check(material!=null,id+" shared native appearance material available for size comparison"):return
	var original:Texture2DArray=material.get_shader_parameter("appearances")
	var resident_before:=Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)
	var images:Array[Image]=[]
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://addons/structures/textures/expansion_v2/provenance.json"))
	for asset:Dictionary in source.assets:
		var pixels:=Image.new();pixels.load_png_from_buffer(FileAccess.get_file_as_bytes(asset["1024"].path));pixels.generate_mipmaps();images.append(pixels)
	var larger:=Texture2DArray.new();check(larger.create_from_images(images)==OK,id+" 1024 appearance comparison array loads")
	for frame in 10:await process_frame
	metrics.append({"id":id,"texture_1024_added_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)-resident_before,"texture_memory_before_1024":resident_before})
	var wall:Vector3=point(lot,Vector3(0,6.65,7))
	var side:Vector3=point(lot,Vector3(-1,6.65,7))-wall
	for size in [512,1024]:
		material.set_shader_parameter("appearances",original if size==512 else larger)
		for distance:float in [2,8,20]:
			game.camera.global_position=wall+side*distance;game.camera.look_at(wall)
			for frame in 30:await process_frame
			await photograph(id+"_material_"+str(size)+"_"+str(int(distance))+"m")
			metrics.append({"id":id,"material_size":size,"distance":distance,"texture_memory_both_arrays_resident":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"logical_texture_bytes":8*(512*512*4-1) if size==512 else 8*(1024*1024*4-1)})
	material.set_shader_parameter("appearances",original)
	# Both arrays coexist only in this review; the production owner loads 512 only.
	larger=null

func inspect_local_removal(game:Node,lot:Dictionary,candidate:Resource)->void:
	var authored:Resource=ClassDB.instantiate("NativeBlockPrefab");authored.compose([candidate],PackedInt32Array([0,lot.origin.x,lot.origin.y,lot.origin.z,lot.rotation]))
	var records:PackedInt32Array=authored.get_records();var cell:=Vector3i.ZERO;var word:=0
	for offset in range(0,records.size(),4):
		var point:=Vector3i(records[offset],records[offset+1],records[offset+2])
		if game.structures.blocks.decode_block(records[offset+3]).shape==29 and (word==0 or point.z>cell.z or (point.z==cell.z and point.x>cell.x)):
			cell=point;word=records[offset+3]
	if not check(word!=0,"town hall has independently addressable cornice corner"):return
	game.camera.global_position=Vector3(cell)+Vector3(-3,3,4);game.camera.look_at(Vector3(cell)+Vector3.ONE*.5)
	for frame in 30:await process_frame
	await photograph("town_hall_corner_intact")
	game.structures.blocks.configure_history(1048576,32)
	check(game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,0])),"one town hall cornice cell removed through native edit")
	game.structures.blocks.flush_bakes()
	for frame in 30:await process_frame
	await photograph("town_hall_corner_removed")
	check(game.structures.blocks.undo() and game.structures.blocks.get_cell(cell)==word,"local cornice undo restores exact styled word")
	game.structures.blocks.flush_bakes()
	var exact:=true
	for offset in range(0,records.size(),4):exact=exact and game.structures.blocks.get_cell(Vector3i(records[offset],records[offset+1],records[offset+2]))==records[offset+3]
	check(exact,"all town hall cells unchanged after local damage and restore")
	for frame in 30:await process_frame
	await photograph("town_hall_corner_restored")

func build_house_baseline()->void:
	folder="res://reports/building_expansion/house_generation";DirAccess.make_dir_recursive_absolute(folder)
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed
	var browser=current_scene
	selected_slot="ExpansionHouse_1703_"+Crypto.new().generate_random_bytes(4).hex_encode()
	var request:=Launch.command(selected_slot,true,Launch.INTEGRATED_PRESET,1703,true,"user://worlds",true,"connected",true,Recipe.DEFAULTS)
	if not check(request.ok,"new isolated normal-world baseline request"):await finish();return
	browser.start_preparation(request,selected_slot)
	var status_path:String=browser.preparation_status
	await wait_for(func():
		if game_ready():return true
		if browser_ready() and current_scene.preparation_pid<0 and FileAccess.file_exists(status_path):
			var state=JSON.parse_string(FileAccess.get_file_as_string(status_path))
			return state is Dictionary and state.get("state","") in ["failed","cancelled"]
		return false,520)
	if check(game_ready(),"normal-world generation and native publication complete"):
		FileAccess.open("res://reports/building_expansion/house_slot.json",FileAccess.WRITE).store_string(JSON.stringify({"slot":selected_slot,"status":status_path}))
	else:print("HOUSE_GENERATION_STATUS ",FileAccess.get_file_as_string(status_path))
	await finish()
