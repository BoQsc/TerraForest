# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func key(code: int,pressed: bool=true) -> void:
	var e:=InputEventKey.new();e.physical_keycode=code;e.pressed=pressed;Input.parse_input_event(e);Input.flush_buffered_events()
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+40000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"world ready")
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.needs_floor_spawn=false
	game.ecosystem.set_process(false)
	var hud=game.player_hud;var attack=game.world_attack
	var uncatalogued:Array[String]=[]
	for asset:String in game.structures._models:
		if not attack.Durability.MODELS.has(asset):uncatalogued.append(asset)
	check(uncatalogued.is_empty(),"every registered model has an explicit durability profile: "+str(uncatalogued))
	check(not hud.damage_feedback.visible and not hud.damage_feedback.is_processing(),"target durability is idle until an accepted hit")
	DirAccess.make_dir_recursive_absolute("res://reports/target_durability")
	var original_position: Vector3=game.player.position
	var base:=Vector3i(game.player.position.floor())+Vector3i(0,10,0)
	game.player.position=Vector3(base)+Vector3(0,0,3)
	game.camera.global_position=Vector3(base)+Vector3(0.5,0.5,2.5);game.camera.look_at(Vector3(base)+Vector3.ONE*0.5)
	game.structures.blocks.set_focus(Vector3(base));Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for slot in 4:
		check(game.structures.blocks.set_cells(PackedInt32Array([base.x,base.y,base.z,33])),"wood block fixture "+str(slot))
		for i in 4:await physics_frame
		hud.equip(slot)
		var t: Dictionary=attack.target()
		check(t.get("kind")=="block","tool "+str(slot)+" targets nearest block")
		var before: int=hud.inventory.snapshot().slots[slot].wear
		attack.next_attack=0
		check(attack.attack() and game.structures.blocks.get_cell(base)!=0 and hud.inventory.snapshot().slots[slot].wear==before+1,"tool "+str(slot)+" damages block and wears without instant removal")
		check(hud.damage_feedback.visible and hud.damage_feedback.remaining==int(t.health)-int(attack.TOOLS[game.equipped_tool].wood) and hud.damage_feedback.maximum==t.health,"block hit displays exact native target durability")
		var expires:int=hud.damage_feedback.expires_us
		check(not attack.attack() and hud.damage_feedback.expires_us==expires,"cooldown rejection does not refresh target feedback")
		if slot==0:
			await RenderingServer.frame_post_draw
			var rect:Rect2=hud.damage_feedback.get_global_rect()
			check(rect.position.distance_to(Vector2(root.size)*0.5)<140 and rect.end.y<root.size.y*0.5 and rect.end.x<=root.size.x,"durability stays near and above the crosshair without covering it")
			root.get_texture().get_image().save_png("res://reports/target_durability/block_hit.png")
			var damage_snapshot:PackedByteArray=attack.durability.capture_storage_snapshot()
			await create_timer(2.35).timeout
			check(not hud.damage_feedback.visible and not hud.damage_feedback.is_processing() and damage_snapshot==attack.durability.capture_storage_snapshot(),"feedback expires without polling or mutating surviving target health")
		for i in 8:
			if game.structures.blocks.get_cell(base)==0:break
			attack.next_attack=0;attack.attack()
		check(game.structures.blocks.get_cell(base)==0,"tool "+str(slot)+" eventually destroys block")
		check(not hud.damage_feedback.visible and not hud.damage_feedback.is_processing() and hud.damage_feedback.expires_us==0,"fatal block hit clears feedback synchronously")
		if slot==0:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://reports/target_durability/block_destroyed.png")
	# No held material can route into an attack.
	hud.equip(4);var snapshot: PackedByteArray=attack.durability.capture_storage_snapshot();attack.next_attack=0
	check(not attack.attack() and snapshot==attack.durability.capture_storage_snapshot(),"placeable material never attacks")
	# Real trunk picking, shared across pickaxe and axe.
	var tree_point:=Vector3(base)+Vector3(5,0,0)
	var poses: Array[Transform3D]=[Transform3D(Basis.IDENTITY,tree_point)]
	game.ecosystem._replace_samples(Vector2i.ZERO,PackedInt64Array([1]),poses)
	game.vegetation.trunk_collision.set_collision_focus(tree_point)
	game.camera.global_position=tree_point+Vector3(0,1,2);game.camera.look_at(tree_point+Vector3.UP)
	for i in 8:await physics_frame
	hud.equip(0);attack.next_attack=0
	check(attack.target().get("kind")=="tree" and attack.attack() and game.vegetation.renderer.roots.has(1),"pickaxe damages a real tree without immediate harvest")
	hud.equip(1)
	for i in 3:attack.next_attack=0;attack.attack()
	check(game.ecosystem.harvest_state.contains(1),"axe finishes the same damaged tree")
	check(not hud.damage_feedback.visible and hud.damage_feedback.expires_us==0,"fatal tree hit clears feedback synchronously")
	# Furniture and protected chest use the same authoritative removal path.
	var shelf=game.structures.model("furniture/shelf/v1")
	var pose:=Transform3D(Basis.IDENTITY,tree_point+Vector3(5,0,0))
	var id: int=game.model_tool.history.insert(shelf,game.model_tool.records(pose,shelf),AABB())
	game.structures.set_model_focus(pose.origin)
	game.camera.global_position=pose.origin+Vector3(0,1,2);game.camera.look_at(pose.origin+Vector3.UP)
	for i in 10:await physics_frame
	check(attack.target().get("kind")=="model","furniture participates in shared nearest hit query")
	var model_target={"kind":"model","key":"model:furniture/shelf/v1:%d"%id,"id":id,"collection":shelf,"health":90,"material":"wood","name":"Shelf"}
	shelf.set_removal_protected(id,true);snapshot=hud.inventory.capture_storage_snapshot()
	var protected_expiry:int=hud.damage_feedback.expires_us
	check(not attack.apply_target(model_target) and hud.inventory.capture_storage_snapshot()==snapshot,"protected container/object consumes no wear or items")
	check(hud.damage_feedback.expires_us==protected_expiry,"protected target does not produce damage feedback")
	shelf.set_removal_protected(id,false)
	attack.apply_target(model_target)
	check(hud.damage_feedback.visible and hud.damage_feedback.remaining==60 and hud.damage_feedback.maximum==90 and hud.damage_feedback.name_label.text=="Shelf","object uses its own native health and target name")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/target_durability/object_hit.png")
	hud.set_open(true);await process_frame
	check(not hud.damage_feedback.visible and not hud.damage_feedback.is_processing(),"inventory clears target feedback")
	hud.set_open(false);attack.apply_target(model_target)
	check(hud.damage_feedback.remaining==30 and hud.damage_feedback.visible,"next hit refreshes the same reusable display")
	game.session_menu.set_open(true);await process_frame
	check(not hud.damage_feedback.visible,"escape menu clears target feedback")
	game.session_menu.set_open(false);attack.apply_target(model_target)
	check(shelf.get_instance(id).is_empty(),"shared attack destroys furniture through salvage transaction")
	check(not hud.damage_feedback.visible and hud.damage_feedback.expires_us==0,"fatal furniture hit clears feedback synchronously")
	if game.actors.pool==null:check(game.actors.enable(),"actor pool enables for damage fixture")
	var actor_point:=tree_point+Vector3(10,2,0)
	var actor_id: int=game.actors.spawn(actor_point);game.actors.select_near(actor_point)
	game.camera.global_position=actor_point+Vector3(0,0,2);game.camera.look_at(actor_point)
	for i in 4:await physics_frame
	var actor_target: Dictionary=attack.target()
	check(actor_target.get("kind")=="actor","active actor resolves stable damage target")
	if actor_target.get("kind")=="actor":
		for i in 7:attack.apply_target(actor_target)
		check(game.actors.store.resolve_identity(actor_id)==0,"actor destruction retires persistent entity")
		check(not hud.damage_feedback.visible,"fatal actor hit clears feedback synchronously")
	var vehicle_point:=tree_point+Vector3(20,2,0)
	check(game.world_vehicle._install_vehicle(game,Transform3D(Basis.IDENTITY,vehicle_point)),"vehicle damage fixture installs")
	game.camera.global_position=vehicle_point+Vector3(2,0.4,0);game.camera.look_at(vehicle_point+Vector3(0,0.4,0))
	for i in 4:await physics_frame
	var car_target: Dictionary=attack.target()
	check(car_target.get("kind")=="vehicle","vehicle resolves stable damage target")
	if car_target.get("kind")=="vehicle":
		for i in 20:attack.apply_target(car_target)
		check(not game.world_vehicle.fleet.get_record(car_target.id).present and game.world_vehicle.car==null,"vehicle destruction removes body and saved identity")
		check(not hud.damage_feedback.visible,"fatal vehicle hit clears feedback synchronously")
	check(game.persistence._capture().sections.has("world_durability"),"world save includes sparse durability")
	# Tool drop/recollect preserves wear using actual pickup stores.
	var worn: int=hud.inventory.snapshot().slots[1].wear
	var dropped: Dictionary=game.pickups.drop_one(hud.inventory,1,hud.inventory.snapshot().revision,Vector3(base))
	check(dropped.ok,"worn tool drops into world")
	var collected: Dictionary=game.pickups.collect_near(Vector3(base),hud.inventory,func(_p: Vector3):return true)
	check(collected.ok and hud.inventory.snapshot().slots[1].wear==worn,"recollecting tool cannot repair it")
	for i in 30:await process_frame
	var cover_point:=Vector3.INF
	for cell in game.ground_cover.resident:
		if game.ground_cover._dirty.has(cell) or game.ground_cover._pending.has(cell):continue
		for species in game.ground_cover.resident[cell]:
			for i in species.ids.size():
				var t: PackedFloat32Array=species.transforms
				var point:=Vector3(t[i*12+3],t[i*12+7],t[i*12+11])
				if point.distance_squared_to(original_position)<cover_point.distance_squared_to(original_position):cover_point=point
	check(cover_point.is_finite(),"natural ground-cover damage fixture available")
	if cover_point.is_finite():
		game.camera.global_position=cover_point+Vector3(0.3,1.5,0.3);game.camera.look_at(cover_point+Vector3.UP*0.1)
		hud.equip(1)
		var cover_target: Dictionary=attack.target()
		check(cover_target.get("kind")=="cover","natural ground cover participates in nearest-target attack")
		if cover_target.get("kind")=="cover":
			for i in 5:
				if game.ground_cover.removed.contains(cover_target.id):break
				attack.apply_target(cover_target)
			check(game.ground_cover.removed.contains(cover_target.id),"ground-cover destruction persists removal")
			check(not hud.damage_feedback.visible,"fatal ground-cover hit clears feedback synchronously")
	# One shared terrain route for every tool, with spatially separate fresh targets.
	game.ground_enabled=false
	for slot in 4:
		game.camera.global_position=original_position+Vector3(slot*1.5,1,0)
		game.camera.look_at(game.camera.global_position+Vector3(0,-1,-0.05))
		hud.refresh();hud.equip(slot)
		var t: Dictionary=attack.target()
		check(t.get("kind")=="terrain","tool "+str(slot)+" can aim at terrain")
		var submitted:=false
		for i in 3:
			attack.next_attack=0;attack.attack()
			if game.terrain.pending_edit:submitted=true;break
		check(submitted,"tool "+str(slot)+" submits excavation through shared attack")
		deadline=Time.get_ticks_msec()+10000
		while game.terrain.pending_edit and Time.get_ticks_msec()<deadline:await process_frame
		check(not game.terrain.pending_edit,"excavation publishes")
	game.ground_enabled=true
	# Replacement tools can be crafted from hand-gatherable supplies.
	hud.inventory.grant_items(PackedInt64Array([201,3,102,2]),hud.inventory.snapshot().revision)
	check(hud.Crafting.craft(hud.inventory,7,1,hud.inventory.snapshot().revision).ok,"replacement pickaxe crafts without a metal dependency")
	hud.refresh();game.camera.global_position=game.player.position+Vector3(0,1.65,0)
	game.session_menu.toggle_developer();hud.equip(3)
	hud.equip(9)
	game._update_edit(0.016);check(not game.pointer.visible and not game.editor_tool_active,"empty development slot disables terrain editing")
	hud.equip(3)
	var ui=game.session_menu.developer_hud
	check(ui.panel.visible and ui.title.text.contains("Build blocks"),"persistent context HUD follows selected developer tool")
	key(KEY_F1);key(KEY_F1,false);check(not ui.panel.visible,"F1 hides development panel")
	key(KEY_F1);key(KEY_F1,false);key(KEY_ALT)
	check(ui.panel.visible and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"Alt exposes mouse for on-screen controls")
	key(KEY_ALT,false);check(Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"Alt release returns to aiming")
	DirAccess.make_dir_recursive_absolute("res://reports/world_attack")
	for i in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/world_attack/developer_blocks.png")
	game.session_menu.toggle_developer();hud.equip(0)
	for i in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/world_attack/gameplay.png")
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("WORLD_ATTACK checks=",checks," failures=",failures);quit(1 if failures else 0)
