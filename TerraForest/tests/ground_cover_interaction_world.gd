# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var persistent: bool="--persist-ground" in OS.get_cmdline_user_args()
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=not persistent
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active,"actual world becomes ready")
	game.set_physics_process(false);game._clear_motion()
	var cover=game.ground_cover
	check(game.ground_enabled,"normal-world ground cover enabled")
	deadline=Time.get_ticks_msec()+15000
	while cover.resident.size()<49 and Time.get_ticks_msec()<deadline: await process_frame
	check(cover.resident.size()==49 and cover.rejected_batches==0,"real support and exclusion masks publish 49 cells")
	var count:=0
	var target:=Vector3.ZERO
	var target_id:=0
	var target_species:=0
	for key in cover.resident:
		for species in cover.resident[key]:
			count+=species.ids.size()
			for i in range(species.ids.size()):
				var t: PackedFloat32Array=species.transforms
				var point:=Vector3(t[i*12+3],t[i*12+7],t[i*12+11])
				if target==Vector3.ZERO or point.distance_squared_to(game.player.global_position)<target.distance_squared_to(game.player.global_position): 
					target=point;target_id=species.ids[i];target_species=cover.resident[key].find(species)
	check(count>0 and count<=3136,"real terrain has bounded ground-cover population")
	game.camera.global_position=target+Vector3(0.7,1.5,1)
	game.camera.look_at(target+Vector3(0,0.2,0))
	for frame in range(60): await RenderingServer.frame_post_draw
	game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var key:=InputEventKey.new();key.physical_keycode=KEY_H;key.pressed=true
	game._unhandled_input(key)
	check(game.ground_mode,"H activates normal-world ground-cover tool")
	check(game.player_hud.ground_hint.visible and "[selected]" in game.player_hud.ground_hint.text,"ground tool keeps its selected species visible")
	game.player_hud.set_open(true)
	check(not game.player_hud.ground_hint.visible,"inventory hides ground controls")
	game.player_hud.set_open(false)
	check(game.player_hud.ground_hint.visible,"closing inventory restores ground controls")
	var before_inventory: Dictionary=game.player_hud.inventory.snapshot()
	key.physical_keycode=KEY_1+target_species;game._unhandled_input(key)
	check(game.player_hud.ground_species==target_species,"number key updates persistent selection")
	check(("Place: 1" in game.player_hud.ground_hint.text) if game.construction_inventory.gameplay else ("Free placement" in game.player_hud.ground_hint.text),"ground controls distinguish inventory cost from free editor")
	var click:=InputEventMouseButton.new();click.pressed=true;click.button_index=MOUSE_BUTTON_LEFT
	game._unhandled_input(click)
	check(cover.removed.contains(target_id),"normal LMB removes aimed natural ground cover")
	click.button_index=MOUSE_BUTTON_RIGHT;game._unhandled_input(click)
	check(cover.removed.profile().placed==1,"normal RMB places selected ground cover on actual terrain")
	check(game.player_hud.inventory.snapshot().slots==before_inventory.slots,"collect/place round trip preserves inventory contents in selected mode")
	deadline=Time.get_ticks_msec()+5000
	while not cover._dirty.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(cover._dirty.is_empty(),"authored placement finishes terrain publication")
	if "--disturb-ground" in OS.get_cmdline_user_args():
		var record: PackedFloat32Array=cover.batches[target_species].get_instance(4294967296)
		var point:=Vector3(record[3],record[7],record[11])
		var cell:=Vector3i(floori(point.x),floori(point.y),floori(point.z))
		var previous_word: int=game.structures.blocks.get_cell(cell)
		var saved_ground: PackedByteArray=cover.removed.capture_storage_snapshot()
		var far_key:=Vector2i(-1,-1)
		for owner: Vector2i in cover.resident:
			if Vector2(owner.x*32+16,owner.y*32+16).distance_to(Vector2(point.x,point.z))>70: far_key=owner;break
		var far_before: Array=cover.resident[far_key].duplicate(true)
		check(game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,1])),"actual block overlaps authored ground-cover position")
		await settle_cover(cover)
		check(not cover.batches[target_species].get_ids().has(4294967296),"building overlap excludes authored item from rendering")
		check(not cover.picker.pick(point+Vector3.UP*0.3,point).hit,"building overlap excludes authored item from interaction")
		check(cover.resident[far_key]==far_before and cover.removed.capture_storage_snapshot()==saved_ground,"local block change preserves distant owner and durable authored state")
		check(game.structures.blocks.set_cells(PackedInt32Array([cell.x,cell.y,cell.z,previous_word])),"overlapping block removed")
		await settle_cover(cover)
		check(cover.batches[target_species].get_ids().has(4294967296),"removing block restores authored item under original identity")
		# Controlled baked volume exercises the real lake publication/mask path.
		var origin:=point-Vector3(2.5,0.5,2.5)
		var volume: RefCounted=ClassDB.instantiate("NativeLakeVolume")
		volume.configure(origin,Vector3i(8,6,8),1.0,origin.y+3.5,origin+Vector3(2.5,2.5,2.5))
		var field:=PackedFloat32Array()
		for z in range(9):
			for y in range(7):
				for x in range(9): field.append(-1.0 if x==0 or x==8 or z==0 or z==8 or y==0 else 1.0)
		check(volume.bake_density(field)==1,"controlled native water volume bakes")
		game.lakes.set_process(false)
		game.lakes._install_lake(9001,origin,Vector3i(8,6,8),1.0,origin.y+3.5,origin+Vector3(2.5,2.5,2.5),volume)
		game.lakes._busy_id=9001;game.lakes._token=9001
		game.lakes._slice_ready(9001,1,game.terrain.epoch,game.terrain.published_revision)
		await settle_cover(cover)
		check(not cover.batches[target_species].get_ids().has(4294967296),"published water excludes submerged authored item")
		check(cover.resident[far_key]==far_before and cover.removed.capture_storage_snapshot()==saved_ground,"water exclusion preserves distant owner and durable authored state")
		game.lakes.remove_lake(9001)
		await settle_cover(cover)
		check(cover.batches[target_species].get_ids().has(4294967296),"removing water restores same authored item")
		game.lakes.set_process(true)
	if "--mine-ground" in OS.get_cmdline_user_args():
		var record: PackedFloat32Array=cover.batches[target_species].get_instance(4294967296)
		var point:=Vector3(record[3],record[7],record[11])
		var before_edits: PackedByteArray=cover.removed.capture_storage_snapshot()
		var distant:=Vector2i(-1,-1)
		for owner: Vector2i in cover.resident:
			if Vector2(owner.x*32+16,owner.y*32+16).distance_to(Vector2(point.x,point.z))>70: distant=owner;break
		var before_distant: Array=cover.resident[distant].duplicate(true)
		check(game.terrain.sculpt_sphere(point,2.5,false),"actual mining edit accepted beneath authored item")
		deadline=Time.get_ticks_msec()+20000
		while game.terrain.pending_edit and Time.get_ticks_msec()<deadline: await process_frame
		check(not game.terrain.pending_edit,"mining publishes before support revalidation")
		await settle_cover(cover)
		check(not cover.batches[target_species].get_ids().has(4294967296),"mined-away support removes floating authored item from rendering")
		check(not cover.picker.pick(point+Vector3.UP*0.3,point).hit,"mined-away support removes interaction proxy")
		check(cover.removed.capture_storage_snapshot()==before_edits and cover.resident[distant]==before_distant,"mining preserves authored record and distant resident identities")
	var render:=[]
	for batch in cover.batches:
		var stats: Dictionary=batch.render_stats();render.append(stats)
		check(stats.resident_instances>0 and stats.resident_transform_bytes<=stats.byte_limit,"species has bounded GPU residency")
	var presentation: Dictionary=load("res://addons/presentation/fullscreen_policy.gd").measurement(root)
	check(presentation.fair_graphical_sample and Engine.max_fps==60,"fullscreen 1080p with 60 FPS cap")
	DirAccess.make_dir_recursive_absolute("res://reports/ground_cover")
	root.get_texture().get_image().save_png("res://reports/ground_cover/interaction_world.png")
	var file:=FileAccess.open("res://reports/ground_cover/interaction_world.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"population":count,"render":render,"presentation":presentation},"  "));file.close()
	if persistent:
		check(game.player_hud.inventory.grant_items(PackedInt64Array([204,3,205,5]),game.player_hud.inventory.snapshot().revision).ok,"seed non-default plant and grass inventory for archive verification")
		var expected:={"slot":game.terrain.save_slot,"ground":cover.removed.capture_storage_snapshot(),"inventory":game.player_hud.inventory.capture_storage_snapshot(),"target":target,"natural_id":target_id,"species":target_species,"seed":game.terrain.backend.world_seed,"active":not "--mine-ground" in OS.get_cmdline_user_args()}
		var saved: Array=[]
		game.terrain.save_completed.connect(func(ok: bool):saved.append(ok))
		game.terrain.changed_since_save=true;game.terrain.save_world()
		deadline=Time.get_ticks_msec()+15000
		while saved.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
		check(not saved.is_empty() and saved[0],"main-world manual save publishes ground edits and inventory")
		var snapshot:=FileAccess.open("res://reports/ground_cover/"+game.terrain.save_slot+".expected",FileAccess.WRITE)
		snapshot.store_var(expected);snapshot.close()
	key.physical_keycode=KEY_H;game._unhandled_input(key)
	check(not game.ground_mode and not game.player_hud.ground_hint.visible,"leaving ground mode removes contextual controls")
	cover.set_process(false)
	game.shutdown_requested=true
	await game.terrain.shutdown_after_edits();game.free()
	for frame in range(2): await process_frame
	print("GROUND_COVER_INTERACTION_WORLD failures=",failures)
	quit(1 if failures else 0)

func settle_cover(cover: Node) -> void:
	var deadline:=Time.get_ticks_msec()+10000
	while (not cover._dirty.is_empty() or not cover._requests.is_empty() or not cover._support_job.is_empty()) and Time.get_ticks_msec()<deadline: await process_frame
	check(cover._dirty.is_empty() and cover._requests.is_empty() and cover._support_job.is_empty(),"local exclusion update completes")
