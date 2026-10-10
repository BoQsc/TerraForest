# SPDX-License-Identifier: 0BSD
extends SceneTree
const DIR="res://reports/settlement_driving/"
var failures:=0
var road_profile:=PackedVector3Array()
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence/staged_placement/manifest.json"))
	var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	if game.terrain.save_slot!=source.slot or game.loading_active:
		check(false,"disposable saved settlement ready");game.terrain.shutdown();quit(1);return
	game.set_physics_process(false);game._clear_motion();game.fly=false;game.needs_floor_spawn=false
	var street: Dictionary=game.road_palette.prepared_streets[0]
	var a: Vector3=street.ends[0];var b: Vector3=street.ends[1];var direction: Vector3=(b-a).normalized()
	var streamed: bool="--streamed-road" in OS.get_cmdline_user_args()
	if streamed:
		game.terrain.backend.disable_snapshot_writes()
		direction=-direction
		for section in 6:road_profile.append(a+direction*section*64)
		if "--surface-road" in OS.get_cmdline_user_args():
			road_profile=await sample_road(game,a,direction)
			if road_profile.size()!=21:
				check(false,"surface route samples ready");game.terrain.shutdown();game.free();quit(1);return
			road_profile[0]=a
			print("SURFACE_PROFILE ",road_profile)
			road_profile=grade_profile(road_profile)
			if road_profile.is_empty():
				check(false,"surface route fits grade and earthwork limits");game.terrain.shutdown();game.free();quit(1);return
		for section in road_profile.size()-1:
			if not game.terrain.construct_road_bed(road_profile[section],road_profile[section+1],4,4,16 if "--surface-road" in OS.get_cmdline_user_args() else 12):
				check(false,"extended road admitted section "+str(section));game.terrain.shutdown();game.free();quit(1);return
			deadline=Time.get_ticks_msec()+30000
			while game.terrain.pending_edit and Time.get_ticks_msec()<deadline:await process_frame
			if game.terrain.pending_edit:
				check(false,"extended road published");game.terrain.shutdown();game.free();quit(1);return
	var start: Vector3=a+direction*5
	if streamed:start.y=road_height(start)
	game.yaw=atan2(-direction.x,-direction.z);game.player.rotation.y=game.yaw
	game.player.position=start-direction*6+Vector3.UP*1.0
	game.terrain.focus=start
	game.camera.global_position=start-direction*6+Vector3.UP*4;game.camera.look_at(start)
	deadline=Time.get_ticks_msec()+15000
	while (not game.world_vehicle.scene_ready() or not game.world_vehicle.ready_bounds(game,AABB(start-Vector3.ONE*4,Vector3.ONE*8))) and Time.get_ticks_msec()<deadline:await process_frame
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var placed: String=game.world_vehicle.spawn(game)
	check(is_instance_valid(game.world_vehicle.car),"place vehicle on authored street: "+placed)
	if not is_instance_valid(game.world_vehicle.car):game.terrain.shutdown();quit(1);return
	var car=game.world_vehicle.car
	check(car.global_basis.z.dot(direction)>0.99,"vehicle faces player's road heading")
	game.player.position=car.position+car.global_basis.x*2.8
	check(game.world_vehicle.enter(game),"enter vehicle on loaded settlement road")
	game.set_physics_process(true)
	for tick in 60:await physics_frame
	if streamed:
		await streamed_drive(game,car,direction)
		game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0);return
	if "--junction-turn" in OS.get_cmdline_user_args():
		await junction_turn(game,car,b)
		game.terrain.backend.disable_snapshot_writes();game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0);return
	var brake_exit: bool="--brake-exit" in OS.get_cmdline_user_args()
	var initial: Vector3=car.position;var rows: Array=[];var held:=0;var max_speed:=0.0
	var press:=InputEventKey.new();press.keycode=KEY_W;press.physical_keycode=KEY_W;press.pressed=true
	for tick in 600:
		game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		Input.parse_input_event(press.duplicate());Input.flush_buffered_events();await physics_frame
		if car.streaming.waiting:held+=1
		max_speed=maxf(max_speed,car.speed_kph)
		if tick%30==0:rows.append({"position":car.position,"speed_kph":car.speed_kph,"waiting":car.streaming.waiting})
		if (car.position-initial).dot(direction)>=(6 if brake_exit else 15):break
	press.pressed=false;Input.parse_input_event(press);Input.flush_buffered_events()
	var braking: Dictionary={}
	if brake_exit:
		var brake_start: Vector3=car.position
		var brake:=InputEventKey.new();brake.keycode=KEY_S;brake.physical_keycode=KEY_S;brake.pressed=true
		var stop_ticks:=0
		for tick in 360:
			game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
			Input.parse_input_event(brake.duplicate());Input.flush_buffered_events();await physics_frame
			stop_ticks=tick+1
			if car.linear_velocity.length()<0.15:break
		brake.pressed=false;Input.parse_input_event(brake);Input.flush_buffered_events()
		braking={"distance":(car.position-brake_start).dot(direction),"ticks":stop_ticks,"speed":car.linear_velocity.length()}
		check(braking.speed<0.15 and braking.distance>=0 and braking.distance<8,"brakes to rest within eight metres without reversing")
	var along: float=(car.position-initial).dot(direction)
	var lateral: float=absf((car.position-start).dot(Vector3(-direction.z,0,direction.x)))
	check(along>=(6 if brake_exit else 15) and lateral<2 and car.position.is_finite(),"drive continuously along street")
	check(car.position.y>start.y-2 and car.position.y<start.y+3,"vehicle remains supported by asphalt road")
	check(game.world_vehicle.driving and game.player.position.distance_to(car.position)<2,"driver and camera remain attached")
	check(held==0,"no collision-readiness holds on short loaded street")
	if brake_exit:
		var message: String=game.world_vehicle.exit_vehicle(game)
		await process_frame;await process_frame
		check(not game.world_vehicle.driving and game.player_hud.visible and game.player_hud.enabled and game.player.collision_mask!=0,"exit stopped vehicle restores walking and toolbelt: "+message)
		var exit_start: Vector3=game.player.position
		game.controls.set_key(KEY_W,true,Time.get_ticks_usec())
		for tick in 20:
			game.app_focused=true;await physics_frame
		game.controls.clear(Time.get_ticks_usec())
		check(game.player.position.distance_to(exit_start)>0.4 and game.player.is_on_floor(),"player walks on road after exiting")
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(DIR+"driving.png")
	var report:={"failures":failures,"road":street,"distance":along,"lateral":lateral,"max_speed_kph":max_speed,"held_ticks":held,"braking":braking,"rows":rows,"scope":"Short real vehicle drive in saved furnished settlement with terrain/forest. Optional brake/exit check. No region-boundary, high-speed, dense fleet, frame or thermal qualification."}
	var f:=FileAccess.open(DIR+"result.json",FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	# Preserve the fixture input save; shutdown intentionally reports save blocked.
	game.terrain.backend.disable_snapshot_writes();game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)

func key_state(code: int,pressed: bool) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event)
func junction_turn(game: Node,car: RigidBody3D,junction: Vector3) -> void:
	# This fixture's first street runs +X, and the connecting street runs +Z.
	# Only keyboard controls are applied; no pose or velocity correction.
	var points: Array[Vector3]=[junction+Vector3(-8,0,0),junction+Vector3(-4,0,1),junction+Vector3(-1,0,4),junction+Vector3(0,0,9),junction+Vector3(0,0,18)]
	var next:=0;var held:=0;var rows: Array=[];var max_speed:=0.0;var max_deviation:=0.0
	for tick in 1800:
		var here: Vector3=car.position;here.y=junction.y
		if here.distance_to(points[next])<2.5:
			next+=1
			if next==points.size():break
		var desired: Vector3=(points[next]-here).normalized()
		var forward: Vector3=car.global_basis.z;forward.y=0;forward=forward.normalized()
		var angle:=atan2(forward.cross(desired).y,forward.dot(desired))
		game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		key_state(KEY_W,car.speed_kph<15);key_state(KEY_S,car.speed_kph>19)
		key_state(KEY_A,angle>0.06);key_state(KEY_D,angle< -0.06);Input.flush_buffered_events()
		await physics_frame
		if car.streaming.waiting:held+=1
		max_speed=maxf(max_speed,car.speed_kph)
		var deviation: float=minf(absf(car.position.z-junction.z),absf(car.position.x-junction.x))
		max_deviation=maxf(max_deviation,deviation)
		if tick%30==0:rows.append({"position":car.position,"speed_kph":car.speed_kph,"waypoint":next,"angle":angle,"waiting":car.streaming.waiting})
	for code in [KEY_W,KEY_S,KEY_A,KEY_D]:key_state(code,false)
	Input.flush_buffered_events()
	check(next==points.size(),"keyboard-driven right turn reaches connecting street")
	check(max_deviation<3 and absf(car.position.y-junction.y)<2,"turn remains on the authored road surface")
	check(held==0,"junction crossing has no collision readiness holds")
	check(car.global_basis.z.dot(Vector3.BACK)>0.8,"vehicle leaves junction facing connecting street")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(DIR+"junction.png")
	var f:=FileAccess.open(DIR+"junction.json",FileAccess.WRITE);f.store_string(JSON.stringify({"failures":failures,"waypoints_reached":next,"max_speed_kph":max_speed,"max_deviation":max_deviation,"held_ticks":held,"rows":rows,"scope":"Keyboard-controlled right turn on loaded saved settlement roads. No physics pose correction, no streamed-boundary or frame-performance claim."},"  "));f.close()

func streamed_drive(game: Node,car: RigidBody3D,direction: Vector3) -> void:
	var initial: Vector3=car.position
	var target: Vector3=initial+direction*245
	target.y=road_height(target)
	var initially_ready: bool=game.world_vehicle.ready_bounds(game,AABB(target-Vector3.ONE*4,Vector3.ONE*8))
	var rows: Array=[];var holds: Array=[];var held:=0;var was_waiting:=false
	var support_segments: Dictionary={};var unsupported: Array=[]
	var max_speed:=0.0;var supported:=0;var ticks:=0
	var deadline:=Time.get_ticks_msec()+40000
	for tick in 3600:
		game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		key_state(KEY_W,true);Input.flush_buffered_events();await physics_frame
		ticks+=1;max_speed=maxf(max_speed,car.speed_kph)
		if car.loaded_wheels>=3:supported+=1
		var segment:=clampi(floori((road_profile[0].x-car.position.x)/absf(road_profile[1].x-road_profile[0].x)),0,road_profile.size()-2)
		if not support_segments.has(segment):support_segments[segment]={"ticks":0,"loaded":0,"no_load":0,"max_clearance":0.0}
		var tally: Dictionary=support_segments[segment];tally.ticks+=1
		if car.loaded_wheels>=3:tally.loaded+=1
		if car.loaded_wheels==0:tally.no_load+=1
		tally.max_clearance=maxf(tally.max_clearance,car.position.y-road_height(car.position))
		if car.loaded_wheels<3:
			unsupported.append({"tick":tick,"segment":segment,"position":car.position,"velocity":car.linear_velocity,"speed":car.speed_kph,"loaded":car.loaded_wheels,"ray_hits":car.grounded_wheels,"springs":car._spring_lengths.duplicate(),"clearance":car.position.y-road_height(car.position)})
		if car.streaming.waiting:held+=1
		if car.streaming.waiting!=was_waiting:
			var velocity: Vector3=car.streaming._linear if car.streaming.waiting else car.linear_velocity
			var bounds: AABB=car.driving_policy.travel_bounds(car.position,velocity,1.0/120)
			holds.append({"tick":tick,"position":car.position,"waiting":car.streaming.waiting,"terrain":game.terrain.is_collision_region_ready(bounds),"structures":game.structures.is_collision_region_ready(bounds),"vegetation":game.vegetation.is_collision_region_ready(bounds)})
			was_waiting=car.streaming.waiting
		if tick%60==0:rows.append({"position":car.position,"speed":car.speed_kph,"waiting":car.streaming.waiting,"wheels":car.loaded_wheels})
		if (car.position-initial).dot(direction)>=245 or car.position.y<road_height(car.position)-4 or Time.get_ticks_msec()>deadline:break
	key_state(KEY_W,false);Input.flush_buffered_events()
	var distance: float=(car.position-initial).dot(direction)
	check(not initially_ready,"destination begins outside combined ready coverage")
	check(distance>=245 and car.position.y>road_height(car.position)-3,"combined world vehicle reaches road destination without falling")
	check(held==0,"combined world travel has zero readiness holds")
	check(supported>=ticks*0.95,"wheel support observed through route")
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(DIR+"streamed.png")
	var result:={"failures":failures,"support_segments":support_segments,"unsupported":unsupported,"road_profile":road_profile,"initial":initial,"end":car.position,"distance":distance,"initially_ready":initially_ready,"held_ticks":held,"ticks":ticks,"supported_ticks":supported,"max_speed_kph":max_speed,"holds":holds,"rows":rows,"scope":"Main-world driving with forest, ground cover, buildings and lakes loaded; temporary authored road extension; original save preserved. No sustained frame/thermal or city-scale qualification."}
	var file:=FileAccess.open(DIR+"streamed.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()

func sample_road(game: Node,a: Vector3,direction: Vector3) -> PackedVector3Array:
	var token: int=preload("res://addons/volumetric_terrain/surface_tokens.gd").allocate()
	var received: Dictionary={}
	var callback:=func(id: int,points: PackedVector3Array,_normals: PackedVector3Array,_epoch: int,_revision: int):
		if id==token:received.points=points
	game.terrain.surface_batch_ready.connect(callback)
	var points:=PackedVector3Array()
	for i in 21:points.append(a+direction*i*16)
	var deadline:=Time.get_ticks_msec()+15000
	while not game.terrain.request_surface_batch(points,token):
		if Time.get_ticks_msec()>deadline:break
		await process_frame
	while received.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
	game.terrain.surface_batch_ready.disconnect(callback)
	return received.get("points",PackedVector3Array())
func road_height(point: Vector3) -> float:
	if road_profile.size()<2:return point.y
	var along:=road_profile[0].x-point.x
	var spacing:=absf(road_profile[1].x-road_profile[0].x)
	var index:=clampi(floori(along/spacing),0,road_profile.size()-2)
	return lerpf(road_profile[index].y,road_profile[index+1].y,clampf((along-index*spacing)/spacing,0,1))

func grade_profile(samples: PackedVector3Array) -> PackedVector3Array:
	# Fixture-only interval feasibility: <=25% grade, <=15 m cut and <=3 m
	# fill. The production road admission constraints remain unchanged.
	var low:=PackedFloat64Array([samples[0].y]);var high:=low.duplicate()
	for i in range(1,samples.size()):
		low.append(maxf(samples[i].y-15,low[i-1]-4))
		high.append(minf(samples[i].y+3,high[i-1]+4))
		# Keep a level entrance for the existing upright parked-vehicle admission.
		if i==1:
			if samples[0].y<low[i] or samples[0].y>high[i]:return PackedVector3Array()
			low[i]=samples[0].y;high[i]=samples[0].y
		if low[i]>high[i]:return PackedVector3Array()
	var result:=samples.duplicate()
	result[-1].y=clampf(samples[-1].y,low[-1],high[-1])
	for i in range(samples.size()-2,-1,-1):
		result[i].y=clampf(samples[i].y,maxf(low[i],result[i+1].y-4),minf(high[i],result[i+1].y+4))
	return result
