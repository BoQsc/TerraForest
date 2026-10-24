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
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(evidence.path_join(name+".png"))
func refresh()->void:game.terrain_placement_preview.remaining=0;game.terrain_placement_preview.update(game,.1)
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview-evidence="):evidence=arg.trim_prefix("--preview-evidence=")
	DirAccess.make_dir_recursive_absolute(evidence)
	ProjectSettings.set_setting("terraforest/impact_effects_settings_path","")
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active and not game.needs_floor_spawn,50),"temporary forest world becomes playable"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.needs_floor_spawn=false
	game.zombies.clear();game.zombies._spawn_clock=100000
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
		chosen=game.terrain_placement.target(game)
		if chosen.get("ok",false) and chosen.position.y>hit.position.y+.05:break
	if not check(chosen.get("ok",false),"real forest floor supplies a reachable clear placement target"):await finish();return
	refresh();var cell:Vector3i=preview.result.cell
	check(preview.visible and preview.caption.visible and not game.target_overlay.enabled and preview.global_position==Vector3(cell),"placement preview works with optional debug overlay disabled and uses snapped target")
	check(preview.mesh.surface_get_array_len(0)==24 and preview.mesh.get_aabb().size.is_equal_approx(Vector3.ONE*game.terrain_placement.STAMP_RADIUS*2),"octahedron has eight flat faces and the native stamp extents")
	var inventory:PackedByteArray=hud.inventory.capture_storage_snapshot();var revision:int=game.terrain.density_revision
	for i in 10:refresh()
	check(inventory==hud.inventory.capture_storage_snapshot() and revision==game.terrain.density_revision and not game.terrain.pending_edit,"preview probing never spends material or edits terrain")
	for item in [201,202,203,211]:
		hud.equip_item(item);refresh()
		check(preview.visible and preview.result.item==item and preview.caption.text.begins_with(hud.RESOURCES[item]),"preview follows carried "+hud.RESOURCES[item])
	hud.equip_item(211);refresh();await capture("topsoil_ready")
	var before:=amount(211)
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_RIGHT;click.pressed=true
	game._unhandled_input(click)
	var payment:Dictionary=game.mining_rewards.payment
	check(not payment.is_empty() and Vector3i(payment.packet.decode_s32(4),payment.packet.decode_s32(8),payment.packet.decode_s32(12))==cell and amount(211)==before-1,"real right click submits exactly the displayed cell and debits one topsoil")
	refresh();check(not preview.visible and not preview.caption.visible,"preview hides while terrain edit is pending")
	check(await wait_for(func():return not game.terrain.pending_edit,20) and not game.mining_rewards.failed,"paid terrain edit publishes normally")
	check(amount(211)==before-1 and game.terrain.density_revision>revision,"the previewed placement adds terrain and spends exactly one unit")
	game.terrain.density_ray_received.connect(func(value:Dictionary):if value.get("token")==91234:reply=value)
	# Sample inside this lattice column, not directly on its X/Z edge where
	# the existing floor-based material probe can read the neighbouring sample.
	game.terrain.request_density_ray(Vector3(cell)+Vector3(.2,2,.2),Vector3(cell)+Vector3(.2,-1,.2),91234,32,true)
	var sampled:bool=await wait_for(func():return not reply.is_empty(),5)
	print("PLACEMENT_READBACK ",JSON.stringify(reply))
	check(sampled and reply.get("surface_material")==10,"native readback confirms topsoil at the previewed placement")
	refresh();await capture("topsoil_placed")
	# A visible small prop on the target must turn the footprint red, without payment.
	var prop:=StaticBody3D.new();prop.collision_layer=2;prop.collision_mask=0
	var collision:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3.ONE*.4;collision.shape=box;prop.add_child(collision)
	var view:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=box.size;view.mesh=mesh;prop.add_child(view)
	game.add_child(prop);prop.global_position=Vector3(cell)+Vector3.UP*2
	game.player.position=Vector3(cell)+Vector3(0,0,2.5)
	game.camera.global_position=prop.global_position+Vector3(0,0,2.5)
	for i in 3:await physics_frame
	game.camera.look_at(prop.global_position);refresh()
	print("PLACEMENT_OBSTRUCTION ",JSON.stringify(preview.result))
	inventory=hud.inventory.capture_storage_snapshot()
	check(preview.visible and not preview.result.ok and preview.result.reason=="Blocked by an object" and not game.terrain_placement.place(game) and inventory==hud.inventory.capture_storage_snapshot(),"obstruction is visible and rejected without charging material")
	await capture("topsoil_blocked");prop.free()
	game.session_menu.set_open(true);refresh();check(not preview.visible and not preview.caption.visible,"ESC hides both world marker and caption")
	game.session_menu.set_open(false);game.app_focused=false;refresh();check(not preview.visible,"focus loss hides placement marker")
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	game.camera.look_at(game.camera.global_position+Vector3.UP+Vector3.FORWARD);refresh();check(not preview.visible and not preview.caption.visible,"no reachable support hides stale marker")
	hud.equip_item(1);refresh();check(not preview.visible,"switching to a weapon removes terrain preview")
	await finish()
func finish()->void:
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"temporary world closes consistently")
	game.free();await process_frame;await process_frame
	print("TERRAIN_PLACEMENT_PREVIEW checks=",checks," failures=",failures);quit(1 if failures else 0)
