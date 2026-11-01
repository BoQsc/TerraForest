# SPDX-License-Identifier: 0BSD
extends "res://tests/runtime_travel_profile.gd"

var contacts:Array[Dictionary]=[]
var publications:Array[Dictionary]=[]
var patch_work:Array[Dictionary]=[]
var active_contact:Dictionary={}
var jumps:=0
var was_grounded:=true
var gameplay_failures:Array[String]=[]
var phase_distance:Dictionary={}
var performance_origin:=Vector3.ZERO
var first_physics_us:=0
var physics_steps:=0

func _initialize()->void:
	frame_limit=12000
	super._initialize()

func key(code:Key,pressed:bool)->void:
	var event:=InputEventKey.new()
	event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()

func physics_tick()->void:
	if first_physics_us==0:first_physics_us=Time.get_ticks_usec()
	physics_steps+=1

func measured_callback(callback:Callable,label:String)->Callable:
	return func(value:Variant)->Variant:
		var began:=Time.get_ticks_usec()
		var result:Variant=callback.call(value)
		stage("zombie callback "+label,(Time.get_ticks_usec()-began)/1000.0)
		return result

func frame()->void:
	var previous_draw_us:=previous
	phase_distance[phase]=float(phase_distance.get(phase,0.0))+game.player.position.distance_to(performance_origin)
	performance_origin=game.player.position
	super.frame()
	rows.back()["first_physics_offset_ms"]=(first_physics_us-previous_draw_us)/1000.0 if first_physics_us else -1.0
	rows.back()["physics_to_process_ms"]=(process_started-first_physics_us)/1000.0 if first_physics_us else -1.0
	rows.back()["physics_steps"]=physics_steps
	rows.back()["window_focused"]=DisplayServer.window_is_focused()
	first_physics_us=0;physics_steps=0
	rows.back()["grounded"]=game.player.is_on_floor()
	rows.back()["velocity"]=game.player.velocity
	rows.back()["pending_edit"]=game.terrain.pending_edit
	rows.back()["loading"]=game.loading_active
	rows.back()["pipeline_draw"]=Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_DRAW)
	rows.back()["pipeline_specialization"]=Performance.get_monitor(Performance.PIPELINE_COMPILATIONS_SPECIALIZATION)
	if was_grounded and not game.player.is_on_floor() and game.player.velocity.y>0:jumps+=1
	was_grounded=game.player.is_on_floor()

func contact(identity:int)->void:
	if active_contact.is_empty() or active_contact.identity!=identity:return
	active_contact.contact_us=Time.get_ticks_usec()
	active_contact.animation_seconds=game.tool_view.human.animation_player.current_animation_position
	var selected:Dictionary=game.world_attack.target()
	active_contact.kind=selected.get("kind","")
	if selected.get("kind")=="terrain":game.terrain.set_interaction_target(selected.position)
	active_contact.accepted=selected.get("kind")=="terrain" and game._model_edit_available() and game.world_attack.apply_target(selected)
	active_contact.dispatch_us=Time.get_ticks_usec()-int(active_contact.contact_us)
	active_contact.ticket=game.terrain.edit_ticket
	if active_contact.accepted:
		var effects_started:=Time.get_ticks_usec()
		game.world_attack.contact_effect.emit(selected)
		active_contact.effects_us=Time.get_ticks_usec()-effects_started

func mined(record:Dictionary)->void:
	publications.append(record.duplicate(true))
	if active_contact.is_empty() or int(record.get("ticket",-1))!=int(active_contact.get("ticket",-2)):return
	active_contact.changed=record.changed
	active_contact.contact_to_draw_ms=(int(record.get("draw_us",0))-int(active_contact.contact_us))/1000.0
	active_contact.publication=record.duplicate(true)

func mine(label:String,count:int)->void:
	phase=label
	move(false);key(KEY_SHIFT,false);key(KEY_SPACE,false)
	var yaw:float=game.player.rotation.y
	for attempt in count:
		await until(func():return not game.terrain.pending_edit and game.player.is_on_floor(),5)
		var selected:Dictionary={}
		for direction in 24:
			game.player.rotation.y=yaw+float((attempt*3+direction)%24)*TAU/24.0
			game.camera.rotation.x=-0.95
			selected=game.world_attack.target()
			if selected.get("kind")=="terrain":break
		if selected.get("kind")!="terrain":
			gameplay_failures.append(label+": no reachable bare terrain")
			break
		active_contact={"phase":label,"identity":10000+contacts.size(),"started_us":Time.get_ticks_usec(),"point":selected.position,"accepted":false,"changed":false}
		game.terrain.note_interaction()
		game.world_attack.impact_preparing.emit(game.camera.global_position,game.camera.global_position-game.camera.global_basis.z*game.world_attack.reach())
		if not game.tool_view.begin_attack(active_contact.identity):
			gameplay_failures.append(label+": animation did not start")
			break
		var finished:=await until(func():return game.tool_view.attack_identity==0 and not game.terrain.pending_edit,5)
		await RenderingServer.frame_post_draw
		if not finished or not active_contact.get("changed",false):gameplay_failures.append(label+": contact did not publish a changed surface")
		contacts.append(active_contact.duplicate(true));active_contact={}
	game.player.rotation.y=yaw;game.camera.rotation.x=0

func sample(label:String,seconds:float)->void:
	print("GAMEPLAY_PHASE ",label)
	if label=="settling":
		await super.sample(label,seconds)
		return
	if label=="idle":
		physics_frame.connect(physics_tick)
		for property:String in ["readiness","navigation_interest","water_depth","spawn_visible"]:
			var callback:Callable=game.zombies.get(property)
			if callback.is_valid():game.zombies.set(property,measured_callback(callback,property))
		performance_origin=game.player.position
		profile_notes="Real standing/walking/sprinting/jumping physics, authored pickaxe contact, production target/durability/stroke/mesh/collision/rewards. Test-only animation initiation bypasses OS mouse capture and input debounce; no click-to-photon claim. Actors, vegetation and normal rendering stay enabled; read-only fixture."
		game.player_hud.equip_item(1)
		game.tool_view.attack_allowed=func():return not game.loading_active and not game.shutdown_requested and not game.session_menu.visible_ui()
		game.tool_view.attack_contact.connect(contact)
		game.terrain.edit_measured.connect(mined)
		game.terrain.work_measured.connect(func(record:Dictionary):patch_work.append(record.duplicate(true)))
		await super.sample("idle",seconds)
		await mine("mining_idle",8)
	elif label=="walking":
		await super.sample("walking",15)
		key(KEY_SHIFT,true)
		await travel("sprinting",15)
		await mine("mining_after_run",8)
		move(true);key(KEY_SHIFT,true);key(KEY_SPACE,true)
		await travel("jumping",15)
		await mine("mining_after_jump",8)
	else:
		await super.sample(label,seconds)

func travel(label:String,seconds:float)->void:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if route.size()>1:
			var offset:Vector3=route[route_index]-game.player.position;offset.y=0
			if offset.length()<1.0:
				route_index+=1
				if route_index>=route.size():route.reverse();route_index=1
				offset=route[route_index]-game.player.position;offset.y=0
			game.player.rotation.y=atan2(-offset.x,-offset.z)
		phase=label
		await process_frame

func finish(success:bool)->void:
	move(false);key(KEY_SHIFT,false);key(KEY_SPACE,false)
	if rows.size()>=frame_limit:gameplay_failures.append("frame trace reached its capture limit")
	if contacts.size()<24:gameplay_failures.append("fewer than 24 measured pickaxe strikes")
	if jumps<3:gameplay_failures.append("fewer than three physical jumps")
	for label:String in ["walking","sprinting","jumping"]:
		if float(phase_distance.get(label,0.0))<40:gameplay_failures.append(label+": physical route covered less than 40 metres")
	FileAccess.open(output.path_join("gameplay.json"),FileAccess.WRITE).store_string(JSON.stringify({"contacts":contacts,"publications":publications,"patch_work":patch_work,"jumps":jumps,"distance_by_phase":phase_distance,"failures":gameplay_failures,"scope":profile_notes},"  "))
	print("GAMEPLAY_PROFILE contacts=",contacts.size()," jumps=",jumps," failures=",gameplay_failures)
	await super.finish(success and gameplay_failures.is_empty())
