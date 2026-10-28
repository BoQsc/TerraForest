extends "res://tests/world_recipe_generation.gd"

var access_checked:=false
var metrics:=[]

func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	super._initialize()

func run()->void:
	var snapshot:=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--city-snapshot="):snapshot=argument.trim_prefix("--city-snapshot=")
	if snapshot.is_empty():await super.run();return
	if not check(snapshot.begins_with("recipe_generated_") and snapshot.is_valid_filename(),"inspection restricted to disposable generated check slot"):await finish();return
	folder="res://reports/approved_city_world";DirAccess.make_dir_recursive_absolute(folder)
	var path:="user://worlds/"+snapshot+".trw"
	var before:=FileAccess.get_sha256(path)
	Options.set_arguments(PackedStringArray(["--world-slot="+snapshot,"--snapshot-readonly","--gameplay-construction","--actors","--vehicle-fleet"]),true)
	change_scene_to_file("res://demo/world.tscn");await scene_changed
	if not check(await wait_for(game_ready,90),"separate process restores generated city world"):await finish();return
	var game=current_scene
	game.background_fps=60
	var settings:Dictionary=Recipe.codec().decode(game.world_recipe.store.capture_snapshot())
	var planned:Dictionary=Plan.build(1703,game.terrain.backend.world_generator,true,true,"user://city_inspection_plan",settings)
	if not check(planned.get("ok",false),"saved recipe reconstructs exact city lots"):await finish();return
	for site:Dictionary in planned.sites:
		for lot:Dictionary in site.lots:
			if not lot.asset.has_meta("city_id"):continue
			var revision:String=lot.asset.get_meta("approved_revision")
			if approved_records.has(revision):continue
			var world_asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
			world_asset.compose([lot.asset],PackedInt32Array([0,lot.origin.x,lot.origin.y,lot.origin.z,lot.rotation]))
			approved_records[revision]=world_asset.get_records();approved_lots[revision]=lot
	check(approved_records.size()==6,"fresh process identifies all six approved city resources")
	await verify_approved_records(game)
	check(before==FileAccess.get_sha256(path),"read-only traversal preserves saved world bytes")
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"checks":checks,"slot":snapshot,"options":settings,"fresh_process_reopen":true},"  "))
	await finish()

func verify_approved_records(game:Node)->void:
	await super.verify_approved_records(game)
	if access_checked:return
	access_checked=true
	for revision:String in approved_lots:
		var lot:Dictionary=approved_lots[revision]
		if not lot.asset.has_meta("city_id"):continue
		await inspect_access(game,lot)
	FileAccess.open(folder.path_join("access.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"metrics":metrics,"routes_exercised":"--city-metrics-only" not in OS.get_cmdline_user_args(),"gpu":RenderingServer.get_video_adapter_name(),"scope":"Populated generated seed 1703, six approved buildings, 180-frame rendered approaches; routes only when routes_exercised=true; no endurance or weak-hardware claim."},"  "))

func point(lot:Dictionary,local:Vector3)->Vector3:
	for turn in lot.rotation:local=Vector3(1-local.z,local.y,local.x)
	return Vector3(lot.origin)+local

func inspect_access(game:Node,lot:Dictionary)->void:
	game.background_fps=60
	var identity:String=lot.asset.get_meta("city_id")
	game.teleport(lot.entrance.segment.finish+Vector3.UP)
	var bounds:AABB=lot.asset.placement_bounds(lot.origin,lot.rotation)
	if not check(await wait_for(func():return not game.loading_active and game.world_vehicle.ready_bounds(game,bounds.grow(3).expand(lot.entrance.segment.finish)),90),identity+" terrain, blocks, models and vegetation collision ready"):return
	game.set_physics_process(false);game._clear_motion();game.fly=true
	game.player.position=lot.entrance.segment.finish+Vector3(15,2,0)
	var camera_pose:Transform3D=game.camera.transform
	var camera_mask:int=game.camera.cull_mask
	game.camera.cull_mask&=~((1<<18)|(1<<19))
	var doors:Node3D=game.doors.collection
	for door_id in doors.get_ids():
		var pose:PackedFloat32Array=doors.get_instance(door_id)
		if pose.size()==12 and bounds.grow(1).has_point(Vector3(pose[3],pose[7],pose[11])) and not game.doors.state.is_open(door_id):
			check(game.doors.state.toggle(doors,door_id,AABB()).get("ok",false),identity+" door opens")
	for frame in 15:await physics_frame
	var body:=CharacterBody3D.new();body.collision_layer=8;body.collision_mask=7;body.floor_snap_length=.35;body.safe_margin=.004;body.floor_max_angle=deg_to_rad(48)
	var capsule:=CapsuleShape3D.new();capsule.radius=.34;capsule.height=1.8
	var shape:=CollisionShape3D.new();shape.shape=capsule;shape.position.y=.9;body.add_child(shape);game.add_child(body)
	var motor:RefCounted=ClassDB.instantiate("NativePlayerMovement")
	var start:Vector3=lot.entrance.segment.finish+Vector3.UP*.04
	var finish:Vector3=point(lot,lot.asset.get_meta("site_entrance"))+Vector3(0,.04,-2.2)
	print("CITY_ACCESS ",identity," start=",start," finish=",finish)
	await walk_route(game,body,motor,start,finish,identity,false)
	await walk_route(game,body,motor,finish,start,identity+" return",false)
	await walk_route(game,body,motor,start,finish,identity,true)
	for route:Dictionary in lot.asset.get_meta("stair_routes",[]):
		await walk_route(game,body,motor,point(lot,route.start),point(lot,route.end),identity+" "+route.kind,false)
	body.free()
	game.camera.global_position=point(lot,lot.asset.get_meta("site_entrance"))+Vector3(0,1.65,-1.1)
	game.camera.look_at(game.camera.global_position+Vector3.FORWARD)
	await photograph(identity+"_interior")
	for driveway:Dictionary in lot.get("vehicle_paths",[]):await drive_bay(game,driveway,identity)
	game.camera.global_position=start+Vector3(8,3,6);game.camera.look_at(finish+Vector3.UP*2)
	await photograph(identity+"_street")
	var target:Vector3=bounds.get_center()
	game.camera.global_position=target+Vector3(38,24,48);game.camera.look_at(target)
	for frame in 90:await process_frame
	await photograph(identity+"_generated")
	var viewport:=root.get_viewport_rid();RenderingServer.viewport_set_measure_render_time(viewport,true)
	var intervals:=[];var gpu:=[];var previous:=Time.get_ticks_usec()
	for frame in 180:
		game.camera.global_position=target+Vector3(38,24,48)*(1.0-frame/360.0);game.camera.look_at(target)
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec();intervals.append((now-previous)/1000.0);previous=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
	intervals.sort();gpu.sort()
	var lod:Dictionary=game.structures.blocks.geometry_lod_stats()
	metrics.append({"id":identity,"fps_cap":Engine.max_fps,"frame_p95_ms":intervals[171],"frame_max_ms":intervals[-1],"gpu_p95_ms":gpu[171],"structure_stats":game.structures.blocks.stats(),"geometry_lods":lod,"vegetation_owners":game.ecosystem.resident.size()})
	check(lod.chunks_with_lods>0 and game.ecosystem.resident.size()<=441,identity+" uses bounded forest coverage and native cached geometry LOD")
	game.camera.transform=camera_pose;game.camera.cull_mask=camera_mask;game.set_physics_process(true)

func walk_route(game:Node,body:CharacterBody3D,motor:RefCounted,start:Vector3,finish:Vector3,label:String,npc:bool)->void:
	if "--city-metrics-only" in OS.get_cmdline_user_args():return
	body.position=start;body.velocity=Vector3.ZERO
	var nav:Node3D
	if npc:
		nav=ClassDB.instantiate("NativeActorNavigator");game.add_child(nav);nav.configure(1);nav.set_exclusions([body.get_rid(),game.player.get_rid()])
	var peak_work:=0
	for tick in 1500:
		await physics_frame
		var delta:=1.0/Engine.physics_ticks_per_second
		var target:=finish
		if npc:
			nav.set_agent(1,body.position,finish,0,true)
			var state:Dictionary=nav.advance(delta,func(area:AABB):return game.world_vehicle.ready_bounds(game,area),Callable())
			peak_work=maxi(peak_work,state.route_work)
			target=nav.steering_target(1)
		var offset:=target-body.position;offset.y=0
		var direction:=offset.normalized() if target.is_finite() else Vector3.ZERO
		var speed:=minf(1.6,offset.length()/delta) if npc else 0.0
		if npc and not nav.guard_motion(1,direction,speed*delta):direction=Vector3.ZERO
		body.velocity=motor.walking_velocity(direction,body.velocity,delta,false,body.is_on_floor(),false)
		if npc:body.velocity.x=direction.x*speed;body.velocity.z=direction.z*speed
		motor.move_grounded(body,delta)
		if Vector2(body.position.x-finish.x,body.position.z-finish.z).length()<.17:break
	var reached:=Vector2(body.position.x-finish.x,body.position.z-finish.z).length()<.2 and absf(body.position.y-finish.y)<.2
	check(reached and peak_work<=48,("native NPC " if npc else "player ")+label+" street/interior route end="+str(body.position))
	if npc:
		if not reached:print("CITY_NPC_STATUS ",nav.status(1))
		nav.free()

func drive_bay(game:Node,driveway:Dictionary,label:String)->void:
	if "--city-metrics-only" in OS.get_cmdline_user_args():return
	var start:Vector3=driveway.finish+Vector3(0,.85,-1)
	var finish:Vector3=driveway.start+Vector3(0,0,-2.4)
	var car=load("res://vehicle_demo/scenes/car.tscn").instantiate()
	car.transform=Transform3D(Basis(Vector3.UP,PI),start);car.collision_layer=4;car.collision_mask=7;game.add_child(car)
	for wheel:RayCast3D in car.wheel_rays:wheel.collision_mask=3
	car.bind_streamed_world(game.terrain,game.structures);car.streaming.bind_vegetation(game.vegetation)
	car.set_controls_enabled(false)
	for tick in 60:await physics_frame
	car.set_controls_enabled(true)
	var reached:=false;var holds:=0
	for tick in 900:
		var event:=InputEventKey.new();event.keycode=KEY_W;event.physical_keycode=KEY_W;event.pressed=car.speed_kph<8;Input.parse_input_event(event)
		await physics_frame
		if car.streaming.waiting:holds+=1
		if car.position.z<=finish.z:reached=true;break
	var release:=InputEventKey.new();release.keycode=KEY_W;release.physical_keycode=KEY_W;release.pressed=false;Input.parse_input_event(release)
	check(reached and absf(car.position.x-finish.x)<1.0 and absf(car.position.y-finish.y)<1.6,"native vehicle "+label+" bay x="+str(finish.x)+" end="+str(car.position)+" holds="+str(holds))
	car.free();await physics_frame

func finish()->void:
	check(preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"city verification never captures desktop pointer")
	await super.finish()
