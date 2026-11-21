# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var failures:=0
var checks:=0
var evidence:="res://reports/terrain_placement_preview"
var reply:Dictionary={}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->bool:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
	return ok
func wait_for(predicate:Callable,seconds:=20)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func amount(item:int)->int:
	var count:=0
	for row:Dictionary in game.player_hud.inventory.snapshot().slots:
		if row.item==item:count+=row.count
	return count
func capture(name:String)->void:
	if "--no-preview-captures" in OS.get_cmdline_user_args():return
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(name+".png"))
func refresh()->void:game.terrain_placement_preview.remaining=0;game.terrain_placement_preview.update(game,.1)
func right_click()->void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_RIGHT;event.pressed=true;game._unhandled_input(event)
	event=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_RIGHT;game._input(event)
# Time actual rendered frames. Read back mesh faces only after the timed draw.
func observe_hand_edit(cell:Vector3i,placing:bool)->void:
	var point:=Vector3(cell)+Vector3(.12,0,.12)
	var ray:=PhysicsRayQueryParameters3D.create(point+Vector3.UP*5,point-Vector3.UP*5,1)
	ray.exclude=[game.player.get_rid()]
	var space:PhysicsDirectSpaceState3D=game.get_world_3d().direct_space_state
	var original:=space.intersect_ray(ray)
	if not check(not original.is_empty(),"Ground supports hand-edit probe"):return
	var ticket:int=game.terrain.edit_ticket
	var impact_clock:={}
	var on_break:=func(_bounds:AABB)->void:
		impact_clock.us=game.terrain.edit_accepted_us
		impact_clock.frame=Engine.get_frames_drawn()
	var clocks:={}
	var field:=func(_ticket:int)->void:clocks.field=Time.get_ticks_usec()
	var installed:=func(_ticket:int,_keys:Array)->void:
		if not clocks.has("install"):clocks.install=Time.get_ticks_usec()
	game.terrain.edit_field_ready.connect(field)
	game.terrain.edit_region_installed.connect(installed)
	game.terrain.region_invalidated.connect(on_break)
	await process_frame
	var start_frame:=Engine.get_frames_drawn()
	var start_us:=Time.get_ticks_usec()
	if placing:
		game.terrain_placement.cached={}
		right_click()
	else:
		var click:=InputEventMouseButton.new()
		click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true
		game._unhandled_input(click)
		click.pressed=false;game._input(click)
	var found:=false
	for frame in 120:
		await RenderingServer.frame_post_draw
		var draw_us:=Time.get_ticks_usec()
		var hit:=space.intersect_ray(ray)
		if hit.is_empty() or game.terrain.edit_ticket<=ticket:continue
		var delta:float=hit.position.y-original.position.y
		if (placing and delta<.02) or (not placing and delta>-.02):continue
		var node:Node3D=hit.collider.get_parent()
		var visual:=false
		if node is MeshInstance3D and node.is_visible_in_tree() and node.mesh:
			var positions:PackedVector3Array=node.mesh.get_faces()
			var origin:=node.to_local(ray.from)
			var direction:=node.to_local(ray.to)-origin
			var nearest:=INF
			for j in range(0,positions.size(),3):
				var intersection=Geometry3D.ray_intersects_triangle(origin,direction,positions[j],positions[j+1],positions[j+2])
				if intersection!=null:nearest=minf(nearest,ray.from.distance_to(node.to_global(intersection)))
			visual=absf(nearest-ray.from.distance_to(hit.position))<.001
		var elapsed:float=(draw_us-(start_us if placing else game.world_attack.last_contact_us))/1000.0
		var draws:int=frame+1 if placing else 1+Engine.get_frames_drawn()-impact_clock.get("frame",start_frame)
		var timing:={
			"action":"place" if placing else "mine","draws":draws,"ms":elapsed,
			"click_ms":(draw_us-start_us)/1000.0,"height_delta":delta,"visual":visual,
			"input_to_admission_ms":(impact_clock.us-start_us)/1000.0 if impact_clock.has("us") else null,
			"admission_to_field_notice_ms":(clocks.field-impact_clock.us)/1000.0 if clocks.has("field") and impact_clock.has("us") else null,
			"field_notice_to_install_ms":(clocks.install-clocks.field)/1000.0 if clocks.has("install") and clocks.has("field") else null,
			"install_to_draw_ms":(draw_us-clocks.install)/1000.0 if clocks.has("install") else null
		}
		print("HAND_EDIT ",JSON.stringify(timing))
		check(visual,"Drawn mesh and collision match within 1 mm")
		check(draws<=2 and elapsed<=33.334,"Hand edit reaches matching draw within two frames")
		found=true
		break
	game.terrain.edit_field_ready.disconnect(field)
	game.terrain.edit_region_installed.disconnect(installed)
	game.terrain.region_invalidated.disconnect(on_break)
	check(found,"Hand edit changed the probed ground")
	check(await wait_for(func():return not game.terrain.pending_edit),"Hand edit transaction drains")

func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="):evidence=arg.trim_prefix("--check-evidence-dir=")
		if arg.begins_with("--preview-evidence="):evidence=arg.trim_prefix("--preview-evidence=")
	if "--measure-hand-edits" not in OS.get_cmdline_user_args():DirAccess.make_dir_recursive_absolute(evidence)
	ProjectSettings.set_setting("terraforest/impact_effects_settings_path","")
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,50),"temporary forest world becomes playable"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.needs_floor_spawn=false
	game.zombies.clear();game.zombies.population_enabled=false
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);game.target_overlay.enabled=false;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var hud=game.player_hud;var preview=game.terrain_placement_preview
	for item in [201,202,203,211]:hud.inventory.grant(item,8,hud.inventory.snapshot().revision)
	hud.refresh();hud.equip_item(211)
	# Find an actual nearby support position that rounds to an exposed lattice unit.
	var feet:Vector3=game.player.position;var chosen:Dictionary={}
	for offset in [Vector3(0,0,-2),Vector3(1,0,-2),Vector3(-1,0,-2),Vector3(2,0,0),Vector3(-2,0,0)]:
		var high:Vector3=feet+offset+Vector3.UP*10
		var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(high,high-Vector3.UP*25,1))
		if hit.is_empty():continue
		game.camera.global_position=feet+Vector3.UP*1.62;game.camera.look_at(hit.position)
		await wait_for(func():return game.terrain_placement.target(game).get("ok",false),3)
		chosen=game.terrain_placement.target(game)
		if chosen.get("ok",false) and chosen.position.y>hit.position.y+.05:break
	if not check(chosen.get("ok",false),"real forest floor supplies a reachable clear placement target"):await finish();return
	refresh();var cell:Vector3i=preview.result.cell
	if "--measure-hand-edits" in OS.get_cmdline_user_args():
		var stock:=amount(211)
		await observe_hand_edit(cell,true)
		check(amount(211)==stock-1,"Placement spends one unit")
		hud.equip_item(1)
		game.camera.global_position=Vector3(cell)+Vector3(.12,2.7,.12)
		game.camera.look_at(Vector3(cell)+Vector3(.121,0,.12))
		var target:Dictionary=game.world_attack.target()
		if check(target.get("kind")=="terrain","Pickaxe targets the placed terrain"):
			game.world_attack.durability.hit(target.key,target.health,target.health-1)
			await observe_hand_edit(cell,false)
		await finish();return
	check(preview.visible and preview.caption.visible and not game.target_overlay.enabled and preview.global_position==preview.result.position,"placement preview works with optional debug overlay disabled and follows the resolved target")
	check((preview.global_position-preview.result.surface).dot(preview.result.normal)>=.35 and preview.global_position.distance_to(Vector3(cell))<=.36,"compact marker stays outside terrain without moving its paid lattice sample")
	check(preview.mesh.surface_get_array_len(0)==24 and preview.mesh.get_aabb().size.is_equal_approx(Vector3.ONE*.7) and game.terrain_placement.STAMP_RADIUS==.75,"compact octahedron has eight faces without shrinking the actual terrain stamp")
	var steady_surface:Vector3=preview.result.surface
	var ready_frames:=0;var reason_counts:Dictionary={};var requests_before:int=game.terrain_placement.sequence
	for frame in 60:
		game.camera.look_at(steady_surface+Vector3(sin(frame*.8)*.22,0,cos(frame*.8)*.22))
		var moving:Dictionary=game.terrain_placement.target(game)
		if moving.get("ok",false):ready_frames+=1
		else:
			var reason:String=moving.get("reason","Hidden");reason_counts[reason]=int(reason_counts.get(reason,0))+1
		await process_frame
	print("MOVING_TERRAIN_TARGET ",JSON.stringify({"ready":ready_frames,"frames":60,"new_queries":game.terrain_placement.sequence-requests_before,"reasons":reason_counts}))
	check(ready_frames>=58 and game.terrain_placement.sequence==requests_before,"continuous aim movement keeps a warm terrain target green without worker roundtrips")
	game.camera.look_at(steady_surface)
	await wait_for(func():return game.terrain_placement.target(game).get("ok",false),3)
	refresh();cell=preview.result.cell
	if game.terrain.backend.native.has_method("try_placement_target"):
		var packet:PackedByteArray=game.terrain.Codec.terrain_target_command(preview.result.surface,preview.result.normal,game.terrain.native_revision,game.terrain.backend.build_epoch)
		var direct:PackedByteArray
		for attempt in 60:
			direct=game.terrain.backend.native.try_placement_target(packet)
			if not direct.is_empty():break
			await process_frame
		var decoded:Dictionary=game.terrain.Codec.decode_terrain_target(direct)
		var reference:Dictionary={}
		var receive:=func(row:Dictionary)->void:
			if row.token==91835:reference.merge(row)
		game.terrain.placement_target_received.connect(receive)
		var sent:bool=game.terrain.request_placement_target(preview.result.surface,preview.result.normal,91835)
		if sent:await wait_for(func():return not reference.is_empty(),3)
		game.terrain.placement_target_received.disconnect(receive)
		check(decoded.get("cell")==cell and decoded.get("origin")==reference.get("origin") and decoded.get("empty")==reference.get("empty"),"immediate query agrees with the worker on the paid cell and occupancy mask")
		check(game.terrain.backend.native.try_placement_target(game.terrain.Codec.command(12)).is_empty(),"immediate target reader refuses mutation and cancellation commands")
	for field in ["epoch","revision","ticket"]:
		var stale:Dictionary=game.terrain_placement.cached.duplicate(true);stale[field]-=1
		check(not game.terrain_placement.matches(stale,game.terrain),"cached mask invalidates on changed "+field)
	var inventory:PackedByteArray=hud.inventory.capture_storage_snapshot();var revision:int=game.terrain.density_revision
	for i in 10:refresh()
	check(inventory==hud.inventory.capture_storage_snapshot() and revision==game.terrain.density_revision and not game.terrain.pending_edit,"preview probing never spends material or edits terrain")
	for item in [201,202,203,211]:
		hud.equip_item(item);refresh()
		check(preview.visible and preview.result.item==item and preview.caption.text.begins_with(hud.RESOURCES[item]),"preview follows carried "+hud.RESOURCES[item])
	hud.equip_item(211);refresh();await capture("topsoil_ready")
	var before:=amount(211)
	var placement=game.terrain_placement
	for cancellation in ["focus","slot","aim","timeout","world"]:
		placement.cached={}
		placement.target(game) # Exercise the pending worker fallback.
		right_click()
		check(not placement.queued.is_empty() and amount(211)==before and game.mining_rewards.payment.is_empty(),"cold click buffers once without early payment: "+cancellation)
		var camera_basis:Basis=game.camera.global_basis
		match cancellation:
			"focus":game.app_focused=false
			"slot":hud.equip_item(201)
			"aim":game.camera.rotate_y(.2)
			"timeout":placement.queued.deadline=Time.get_ticks_msec()-1
			"world":placement.queued.epoch-=1
		placement.update(game)
		check(placement.queued.is_empty() and amount(211)==before and game.mining_rewards.payment.is_empty(),"changed context cancels the buffered click without spending: "+cancellation)
		game.app_focused=true;hud.equip_item(211);game.camera.global_basis=camera_basis
	placement.cached={}
	placement.target(game) # Exercise the pending worker fallback.
	var submission:={}
	var observe_submission:=func(_bounds:AABB)->void:
		if game.mining_rewards.payment.is_empty():return
		submission.payment=game.mining_rewards.payment.duplicate()
		submission.stock=amount(211)
		refresh()
		submission.amber=preview.visible and not preview.caption.visible and preview.result.get("reason")=="Terrain is updating"
	game.terrain.region_invalidated.connect(observe_submission)
	right_click()
	check(not placement.queued.is_empty() and amount(211)==before,"first click while the terrain query is pending is retained")
	check(await wait_for(func():return submission.has("payment"),3),"buffered first click submits automatically when its target resolves")
	game.terrain.region_invalidated.disconnect(observe_submission)
	var payment:Dictionary=submission.get("payment",{})
	check(not payment.is_empty() and Vector3i(payment.packet.decode_s32(4),payment.packet.decode_s32(8),payment.packet.decode_s32(12))==cell and submission.stock==before-1,"real right click submits exactly the displayed cell and debits one topsoil")
	check(submission.get("amber",false),"preview remains visible and amber while terrain edit is pending")
	check(await wait_for(func():return not game.terrain.pending_edit,20) and not game.mining_rewards.failed,"paid terrain edit publishes normally")
	check(amount(211)==before-1 and game.terrain.density_revision>revision,"the previewed placement adds terrain and spends exactly one unit")
	for frame in 10:await process_frame
	check(placement.queued.is_empty() and amount(211)==before-1,"buffered placement cannot repeat or charge twice")
	game.terrain.density_ray_received.connect(func(value:Dictionary):if value.get("token")==91234:reply=value)
	# Sample inside this lattice column, not directly on its X/Z edge where
	# the existing floor-based material probe can read the neighbouring sample.
	game.terrain.request_density_ray(Vector3(cell)+Vector3(.2,2,.2),Vector3(cell)+Vector3(.2,-1,.2),91234,32,true)
	var sampled:bool=await wait_for(func():return not reply.is_empty(),5)
	print("PLACEMENT_READBACK ",JSON.stringify(reply))
	check(sampled and reply.get("surface_material")==10,"native readback confirms topsoil at the previewed placement")
	refresh();await capture("topsoil_placed")
	var last_cell:=cell
	for layer in 3:
		game.player.position=Vector3(last_cell)+Vector3(0,0,2.5)
		game.camera.global_position=Vector3(last_cell)+Vector3(0,2.8,.2);game.camera.look_at(Vector3(last_cell))
		if not check(await wait_for(func():return game.terrain_placement.target(game).get("ok",false),5),"placed topsoil accepts another terrain target"):print("STACK_TARGET ",game.terrain_placement.target(game));break
		refresh();var stacked:Vector3i=preview.result.cell
		check(stacked.y==last_cell.y+1 and (preview.global_position-preview.result.surface).dot(preview.result.normal)>=.35,"stack advances exactly one layer with an exposed marker")
		before=amount(211);var previous_revision:int=game.terrain.density_revision
		right_click()
		check(await wait_for(func():return not game.terrain.pending_edit,20) and amount(211)==before-1 and game.terrain.density_revision>previous_revision,"right click grows player-placed topsoil without a no-op refund")
		last_cell=stacked
	game.player.position=Vector3(last_cell)+Vector3(0,0,2.5)
	game.camera.global_position=Vector3(last_cell)+Vector3(0,2.8,.2);game.camera.look_at(Vector3(last_cell))
	if check(await wait_for(func():return placement.target(game).get("ok",false),5),"rapid stacking starts from a valid topsoil target"):
		var rapid_cell:Vector3i=placement.target(game).cell
		before=amount(211)
		right_click()
		right_click()
		check(game.terrain.pending_edit and not placement.queued.is_empty() and amount(211)==before-1,"second explicit click is retained while the first stamp publishes")
		check(await wait_for(func():return amount(211)==before-2 and not game.terrain.pending_edit and placement.queued.is_empty(),20),"two quick clicks publish exactly two paid stamps without retrying input")
		for frame in 10:await process_frame
		check(amount(211)==before-2 and game.mining_rewards.payment.is_empty(),"rapid stacking does not repeat its buffered second click")
		last_cell=rapid_cell+Vector3i.UP
	game.camera.global_position=Vector3(last_cell)+Vector3(0,2.8,.2);game.camera.look_at(Vector3(last_cell))
	await wait_for(func():return placement.target(game).get("ok",false),3);refresh()
	await capture("topsoil_stack")
	hud.inventory.grant(101,4,hud.inventory.snapshot().revision);hud.refresh();hud.equip_item(101)
	game.camera.global_position=Vector3(last_cell)+Vector3(.15,2.8,.2);game.camera.look_at(Vector3(last_cell)+Vector3(.15,0,.15))
	var block:Dictionary=game._structure_target(false);print("TOPSOIL_BLOCK_TARGET ",JSON.stringify(block))
	if check(block.get("placement_ok",false),"building block can target newly placed topsoil"):
		before=amount(101);game._edit_structure(false)
		check(game.structures.blocks.get_cell(block.target)==1 and amount(101)==before-1,"real block placement on topsoil preserves grid alignment and pays once")
	hud.equip_item(211)
	# A visible small prop on the target must turn the footprint red, without payment.
	var prop:=StaticBody3D.new();prop.collision_layer=2;prop.collision_mask=0
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3.ONE*.4;collision.shape=box;prop.add_child(collision)
	var view:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=box.size;view.mesh=mesh;prop.add_child(view)
	game.add_child(prop);prop.global_position=Vector3(cell)+Vector3(4,2,.3)
	game.player.position=prop.global_position+Vector3(0,-1.5,2.5)
	game.camera.global_position=prop.global_position+Vector3(0,0,2.5)
	for i in 3:await physics_frame
	game.camera.look_at(prop.global_position);refresh()
	await wait_for(func():return game.terrain_placement.target(game).get("reason")!="Checking terrain",3);refresh()
	print("PLACEMENT_OBSTRUCTION ",JSON.stringify(preview.result))
	inventory=hud.inventory.capture_storage_snapshot()
	var notice:String=game._lake_notice;var notice_until:int=game._lake_notice_until
	check(preview.visible and not preview.result.ok and preview.result.reason=="Blocked by an object" and not game.terrain_placement.place(game) and inventory==hud.inventory.capture_storage_snapshot(),"obstruction is visible and rejected without charging material")
	check(not preview.caption.visible and preview.caption.text.is_empty() and game._lake_notice==notice and game._lake_notice_until==notice_until,"blocked target uses color without caption or click notice")
	await capture("topsoil_blocked");prop.free()
	game.session_menu.set_open(true);refresh();check(not preview.visible and not preview.caption.visible,"ESC hides both world marker and caption")
	game.session_menu.set_open(false);game.app_focused=false;refresh();check(not preview.visible,"focus loss hides placement marker")
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	game.camera.global_position=Vector3(last_cell)+Vector3(4,4,4);game.camera.look_at(game.camera.global_position+Vector3.UP+Vector3.BACK);refresh();check(not preview.visible and not preview.caption.visible,"no reachable support hides stale marker")
	hud.equip_item(1);refresh();check(not preview.visible,"switching to a weapon removes terrain preview")
	await finish()
func finish()->void:
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"temporary world closes consistently")
	game.free();await process_frame;await process_frame
	print("TERRAIN_PLACEMENT_PREVIEW checks=",checks," failures=",failures);quit(1 if failures else 0)
