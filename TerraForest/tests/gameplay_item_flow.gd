# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func key(code: int,pressed: bool=true) -> void:
	var e:=InputEventKey.new();e.physical_keycode=code;e.pressed=pressed;Input.parse_input_event(e);Input.flush_buffered_events()
func total(hud: Node,id: int) -> int:
	var count:=0
	for row in hud.inventory.snapshot().slots:
		if row.item==id:count+=row.count
	return count
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+40000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"world ready")
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.needs_floor_spawn=false;game.fly=false
	var hud=game.player_hud
	var valid:=true
	for id in game.pickups.ITEMS:
		var renderer: MultiMeshInstance3D=game.pickups.renderers[id]
		var mesh: Mesh=renderer.multimesh.mesh
		if mesh.get_surface_count()!=1 or mesh.get_aabb().size.length()>=0.62:print("DROP_MESH ",id," surfaces=",mesh.get_surface_count()," bounds=",mesh.get_aabb())
		valid=valid and mesh is ArrayMesh and mesh.get_aabb().size.length()<0.62 and mesh.get_surface_count()==1
	check(valid,"every dropped item uses one baked mesh surface in existing native MultiMesh batches")
	var point: Vector3=game.player.position
	# Find the generator surface directly; this also works when the spawn is adjusted.
	var probe: RefCounted=ClassDB.instantiate("TerrainCore");probe.execute(Codec.command(6,[1703,4]))
	var top:=0
	for y in range(255,0,-1):
		var packet:=Codec.point_command(Vector3(800,y,1310));packet.encode_u32(0,26)
		if probe.execute(packet).decode_float(16)<0:top=y;break
	var counts: PackedInt64Array=Codec.excavation_samples(probe.execute(Codec.brush(Vector3(800,top,1310),Vector3(800,top,1310),1.2,0,false,1)))
	check(counts.size()==16 and counts[10]>0 and counts[0]==0,"native upper surface removal is topsoil, not stone")
	counts=Codec.excavation_samples(probe.execute(Codec.brush(Vector3(800,top-8,1310),Vector3(800,top-8,1310),1.2,0,false,1)))
	check(counts[0]>0 and counts[10]==0,"deeper natural rock remains stone")
	probe=null
	var before:=total(hud,211)
	var center:=point-Vector3.UP*0.5
	check(game.terrain.sculpt_sphere(center,1.2,false),"gameplay mining accepted")
	deadline=Time.get_ticks_msec()+10000
	while game.terrain.pending_edit and Time.get_ticks_msec()<deadline:await process_frame
	var removed: PackedInt64Array=game.terrain.last_edit_outcome.get("removed_samples",PackedInt64Array())
	check(removed.size()==16 and removed[10]>0 and total(hud,211)-before==removed[10] and hud.reward_inbox.get_pending().is_empty(),"published excavation delivers exact topsoil directly into inventory")
	var saved: PackedByteArray=hud.inventory.capture_storage_snapshot()
	game.mining_rewards.published(AABB(),0)
	check(saved==hud.inventory.capture_storage_snapshot(),"duplicate publication cannot duplicate rewards")
	# Internal overflow survives and automatically drains without a Claim button.
	var isolated=preload("res://addons/player_runtime/player_hud.gd").new();isolated.prepare()
	var inv=isolated.inventory
	var space:=0
	for row in inv.snapshot().slots:
		if row.count==0:space+=999
	inv.grant(211,space,inv.snapshot().revision)
	check(isolated.reward_inbox.accept(PackedInt64Array([211,7]),1).ok and isolated.deliver_mining_rewards()==0,"full inventory retains reward receipt safely")
	var target:=-1
	for i in 32:
		if inv.snapshot().slots[i].item==211:target=i;break
	inv.consume(target,4,inv.snapshot().revision)
	check(isolated.deliver_mining_rewards()==4 and isolated.reward_inbox.get_pending()[1]==3,"new space automatically receives only fitting overflow")
	var inbox_bytes: PackedByteArray=isolated.reward_inbox.capture_storage_snapshot();isolated.reward_inbox.restore_storage_snapshot(inbox_bytes)
	inv.consume(target,3,inv.snapshot().revision)
	check(isolated.deliver_mining_rewards()==3 and isolated.reward_inbox.get_pending().is_empty(),"restored overflow drains without loss")
	isolated.free()
	# Empty hands use exactly the same block target and damage path.
	var base:=Vector3i(point.floor())+Vector3i(0,8,0)
	game.structures.blocks.set_focus(Vector3(base));game.structures.blocks.set_cells(PackedInt32Array([base.x,base.y,base.z,33]))
	game.player.position=Vector3(base)+Vector3(0,0,3)
	game.camera.global_position=Vector3(base)+Vector3(0.5,0.5,2.5);game.camera.look_at(Vector3(base)+Vector3.ONE*0.5)
	for i in 5:await physics_frame
	hud.equip(9);Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	check(game.equipped_tool==0 and game.tool_view.tools[0].visible,"empty slot shows hands")
	saved=hud.inventory.capture_storage_snapshot();game.world_attack.next_attack=0
	check(game.world_attack.target().get("kind")=="block" and game.world_attack.attack() and saved==hud.inventory.capture_storage_snapshot(),"unarmed attack hits shared target without tool wear")
	# Selected wood must route a real RMB event into paid cube placement.
	hud.equip(5);var wood:=total(hud,102);var hit: Dictionary=game._structure_target(false)
	var mouse:=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_RIGHT;mouse.pressed=true;Input.parse_input_event(mouse);Input.flush_buffered_events()
	check(not hit.is_empty() and game.structures.blocks.get_cell(hit.target)==33 and total(hud,102)==wood-1,"right click places held wood and consumes one unit")
	mouse=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_RIGHT;Input.parse_input_event(mouse)
	# Input overlay must never activate a focused control with Space.
	game.session_menu.toggle_developer();hud.equip(0)
	var ui=game.session_menu.developer_hud
	key(KEY_ALT)
	for child in ui.content.get_children():
		if child is SpinBox:child.get_line_edit().grab_focus()
	key(KEY_SPACE);check(game.controls.held.has(KEY_SPACE) and game._movement_input_available(),"Space reaches player while Alt exposes developer HUD")
	key(KEY_SPACE,false);key(KEY_ALT,false)
	check(root.gui_get_focus_owner()==null,"Alt release clears HUD keyboard focus")
	key(KEY_SPACE);check(game.controls.held.has(KEY_SPACE),"Space reaches player after Alt release");key(KEY_SPACE,false)
	game.session_menu.toggle_developer()
	# Return to unmined nearby ground for a real G drop.
	game.player.position=point+Vector3(3,0,0);game.camera.position=Vector3(0,1.65,0);game.player.rotation=Vector3.ZERO
	hud.equip(5);wood=total(hud,102)
	key(KEY_G);key(KEY_G,false)
	check(not game.fly and total(hud,102)==wood-1 and game.pickups.stores[102].statistics().active>0,"G drops one held item and does not toggle flight")
	key(KEY_G);key(KEY_G,false)
	check(total(hud,102)==wood-2,"repeated G finds adjacent clear ground")
	hud.equip(9)
	DirAccess.make_dir_recursive_absolute("res://reports/gameplay_item_flow")
	for i in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/gameplay_item_flow/hands.png")
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("GAMEPLAY_ITEM_FLOW checks=",checks," failures=",failures);quit(1 if failures else 0)
