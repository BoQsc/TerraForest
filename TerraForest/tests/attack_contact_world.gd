# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var game:Node
var impacts:Array=[]
var folder:="res://reports/attack_contact_world"
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:run.call_deferred()
func until(condition:Callable,seconds:float=3)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<deadline:await process_frame
	return condition.call()
func damage(cell:Vector3i)->int:
	var data:PackedByteArray=game.world_attack.durability.capture_storage_snapshot();var at:=8
	for i in data.decode_u32(4):
		var length:int=data.decode_u32(at)
		if data.slice(at+12,at+12+length).get_string_from_utf8()==game.world_attack.block_key(cell):return data.decode_u32(at+8)
		at+=12+length
	return 0
func aim(cell:Vector3i)->void:
	game.player.position=Vector3(cell)+Vector3(0.5,-1.15,2.5)
	game.camera.global_position=Vector3(cell)+Vector3(0.5,0.5,2.5);game.camera.look_at(Vector3(cell)+Vector3.ONE*0.5)
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func mouse(pressed:bool)->void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
func key(code:int,pressed:bool)->void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(name+".png"))
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--attack-evidence-dir="):folder=arg.trim_prefix("--attack-evidence-dir=")
	DirAccess.make_dir_recursive_absolute(folder)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	check(await until(func():return not game.loading_active,50),"normal world ready")
	if game.loading_active:game.terrain.shutdown();game.free();quit(1);return
	game.set_physics_process(false);game._clear_motion();game.needs_floor_spawn=false;game.ground_enabled=false
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);game.zombies.clear();game.zombies._spawn_clock=100000
	var hud=game.player_hud;var attack=game.world_attack
	var cell:=Vector3i(game.player.position.floor())+Vector3i(0,8,0);var other:=cell+Vector3i(4,0,0)
	check(game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,65,other.x,other.y,other.z,65])),"two real concrete targets installed")
	game.structures.blocks.set_focus(Vector3(cell))
	for i in 5:await physics_frame
	hud.equip(0);aim(cell)
	attack.impact_resolved.connect(func(identity:int,accepted:bool):impacts.append({"id":identity,"accepted":accepted,"clip":game.tool_view.human.active_clip,"animation_seconds":game.tool_view.human.animation_player.current_animation_position,"time_us":Time.get_ticks_usec()}))
	var wear:int=hud.inventory.snapshot().slots[0].wear
	mouse(true);mouse(false)
	check(not attack.pending.is_empty() and damage(cell)==0 and hud.inventory.snapshot().slots[0].wear==wear,"mouse-down starts windup without damage or wear")
	if not attack.pending.is_empty():attack.resolve_contact(attack.pending.identity)
	check(damage(cell)==0 and impacts.is_empty(),"an early animation callback cannot authorize damage")
	var rejected:=true
	for i in 8:rejected=rejected and not attack.attack()
	check(rejected,"repeated input cannot create hidden hits during windup")
	check(await until(func():return game.tool_view.human.animation_player.current_animation_position>=0.2),"visible windup advances")
	check(damage(cell)==0 and impacts.is_empty(),"target stays intact during visible windup")
	await capture("windup")
	check(await until(func():return impacts.size()==1),"single click resolves at visible contact")
	check(impacts.size()==1 and impacts[0].accepted and is_equal_approx(impacts[0].animation_seconds,32.0/60) and damage(cell)==30 and hud.inventory.snapshot().slots[0].wear==wear+1,"exact contact pose applies one native hit and one wear point")
	await capture("contact")
	check(not attack.pending.is_empty() and not attack.attack(),"recovery blocks another swing")
	check(await until(func():return attack.pending.is_empty()) and impacts.size()==1,"recovery finishes without extra damage")
	await capture("recovered")
	# Aim changes are evaluated at contact, not saved from the original click.
	aim(cell);check(attack.attack(),"retargeting swing starts");aim(other)
	check(await until(func():return attack.pending.is_empty()) and damage(cell)==30 and damage(other)==30,"only the target aimed at contact receives damage")
	# A target which leaves reach during windup must miss without consuming wear.
	wear=hud.inventory.snapshot().slots[0].wear;aim(other);check(attack.attack(),"reach-check swing starts")
	game.player.position.z+=6
	check(await until(func():return attack.pending.is_empty()) and not attack.last_hit and damage(other)==30 and hud.inventory.snapshot().slots[0].wear==wear,"moving out of reach before contact misses without wear")
	for reason in ["equipment","session","inventory","ownership","Alt","focus","epoch"]:
		hud.equip(0);aim(other);attack.next_attack=0
		var saved:PackedByteArray=attack.durability.capture_storage_snapshot();var previous:=impacts.size()
		check(attack.attack(),"cancellation windup starts: "+reason)
		match reason:
			"equipment":hud.equip(1)
			"session":game.session_menu.set_open(true);game.session_menu.set_open(false)
			"inventory":hud.set_open(true);hud.set_open(false)
			"ownership":check(hud.inventory.transfer(0,10,1,hud.inventory.snapshot().revision).ok,"native ownership changes without a HUD refresh")
			"Alt":key(KEY_ALT,true);key(KEY_ALT,false)
			"focus":game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT);game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
			"epoch":game.terrain.reload_world(false)
		check(await until(func():return attack.pending.is_empty()),"pending strike cancelled: "+reason)
		check(saved==attack.durability.capture_storage_snapshot() and impacts.size()==previous,"cancelled action changes no target: "+reason)
		if reason=="ownership":check(hud.inventory.transfer(10,0,1,hud.inventory.snapshot().revision).ok,"owned tool returns intact after cancellation")
		if reason=="epoch":check(await until(func():return not game.loading_active,35),"real reload completes without a pending attack")
	# Actual held input uses full clip recovery rather than a separate damage timer.
	cell=Vector3i(game.player.position.floor())+Vector3i(0,8,0)
	check(game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,65])),"held-input target installed after reload")
	var platform:=PackedInt32Array()
	for x in range(-1,2):
		for z in range(1,5):platform.append_array(PackedInt32Array([cell.x+x,cell.y-2,cell.z+z,1]))
	check(game.structures.blocks.set_cells(platform),"held-input fixture has real standing collision")
	game.structures.blocks.set_focus(Vector3(cell))
	for i in 20:await physics_frame
	hud.equip(0);aim(cell);wear=hud.inventory.snapshot().slots[0].wear
	game.needs_floor_spawn=false
	game.player.position.y=cell.y-1;game.camera.look_at(Vector3(cell)+Vector3.ONE*0.5)
	game.set_physics_process(true)
	print("HELD_START ",JSON.stringify({"cell":cell,"player":game.player.position,"camera":game.camera.global_position,"basis":game.camera.global_basis,"target":attack.target()}))
	var previous:=impacts.size();mouse(true)
	var held_until:=Time.get_ticks_msec()+3150
	while Time.get_ticks_msec()<held_until:await process_frame
	mouse(false);check(await until(func():return attack.pending.is_empty()),"last held swing completes after button release")
	var count:=impacts.size()-previous
	print("HELD_SWINGS ",JSON.stringify({"contacts":count,"damage":damage(cell),"wear":hud.inventory.snapshot().slots[0].wear-wear,"target":attack.target(),"on_floor":game.player.is_on_floor(),"player":game.player.position,"camera":game.camera.global_position,"basis":game.camera.global_basis}))
	check(count>=2 and count<=3 and damage(cell)==30*count and hud.inventory.snapshot().slots[0].wear==wear+count,"held input produces exactly one hit and wear per complete swing")
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"impacts":impacts,"scope":"Actual temporary-world input, native damage/wear and animation contact/recovery; no performance or art acceptance."},"  "))
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"clean shutdown")
	game.free();await process_frame;await process_frame
	print("ATTACK_CONTACT_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
