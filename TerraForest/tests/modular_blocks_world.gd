extends SceneTree

var game: Node3D
var failures := 0
var checks := 0
var output := "res://reports/modular_blocks_world"
var pictures: Dictionary = {}
var driver_path := "res://tests/swing_driver.gd"
const MODULAR_COUNT = 10

func _initialize() -> void:
	run.call_deferred()

func check(accepted: bool, label: String) -> void:
	checks += 1
	if not accepted:
		failures += 1
	print("PASS " if accepted else "FAIL ", label)

func click(button: int) -> void:
	var event := InputEventMouseButton.new()
	event.button_index=button;event.pressed=true
	Input.parse_input_event(event)
	await process_frame
	event=InputEventMouseButton.new();event.button_index=button;event.pressed=false
	Input.parse_input_event(event)
	await process_frame

func key(code: int, pressed: bool, shift: bool = false) -> void:
	var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=pressed;event.shift_pressed=shift
	Input.parse_input_event(event)
	await process_frame

func picture(name: String) -> void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	pictures[name]=root.get_texture().get_image()

func material_count(inventory: RefCounted, item: int) -> int:
	var total:=0
	for slot:Dictionary in inventory.snapshot().slots:
		if slot.item==item:total+=slot.count
	return total

func quick_options() -> Array[OptionButton]:
	var choices:Array[OptionButton]=[]
	for child in game.session_menu.developer_hud.content.get_children():
		if child is OptionButton:choices.append(child)
	return choices

func choose_quick(field: int, value: int) -> void:
	await process_frame
	var choices:=quick_options()
	check(choices.size()==3 and choices[field].item_count>value,"visible ALT controls offer requested shape/orientation")
	if choices.size()!=3 or choices[field].item_count<=value:return
	choices[field].select(value);choices[field].item_selected.emit(value)
	await process_frame

func restore_check() -> void:
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld")
	var saved:=FileAccess.get_file_as_bytes(output.path_join("blocks.tfbl"))
	check(not saved.is_empty() and blocks.restore_snapshot(saved),"fresh-process native save restore")
	var expected:Array=JSON.parse_string(FileAccess.get_file_as_string(output.path_join("placed_records.json")))
	for record:Array in expected:
		check(blocks.get_cell(Vector3i(record[0],record[1],record[2]))==int(record[3]),"fresh process preserves modular cell identity")
	check(blocks.capture_snapshot()==saved,"fresh process recreates exact binary bytes")
	blocks.free()
	print("MODULAR_BLOCKS_RESTORE failures=",failures)
	quit(1 if failures else 0)

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--modular-output="):output=argument.trim_prefix("--modular-output=")
		if argument.begins_with("--modular-driver="):driver_path=argument.trim_prefix("--modular-driver=")
	DirAccess.make_dir_recursive_absolute(output)
	if "--verify-saved-modular" in OS.get_cmdline_user_args():
		restore_check();return
	var swing:Script=load(driver_path)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"actual gameplay world finished loading")
	if game.loading_active:
		await finish();return
	game.set_physics_process(false);game.fly=true;game._clear_motion();game.app_focused=true;game.needs_floor_spawn=false
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false)
	var hud=game.player_hud
	var blocks=game.structures.blocks
	check(hud.inventory.grant_items(PackedInt64Array([102,20]),hud.inventory.snapshot().revision).ok,"wood supply added through native inventory")
	var wood_slot:=-1;var axe_slot:=-1
	for slot in hud.inventory.snapshot().slots.size():
		var item:int=hud.inventory.snapshot().slots[slot].item
		if item==102:wood_slot=slot
		if item==2:axe_slot=slot
	check(wood_slot>=0 and axe_slot>=0,"player has building material and an axe")
	if wood_slot<0 or axe_slot<0:
		await finish();return
	var base:=Vector3i(game.player.position.floor())+Vector3i(0,32,-8)
	var targets: Array[Vector3i]=[]
	var supports:=PackedInt32Array()
	for index in MODULAR_COUNT:
		var support:=base+Vector3i(index*3,0,0)
		supports.append_array(PackedInt32Array([support.x,support.y,support.z,65]))
		targets.append(support+Vector3i.UP)
	check(blocks.set_cells(supports),"isolated test supports do not replace any house")
	blocks.set_focus(Vector3(base))
	var start_material:int=material_count(hud.inventory,102)
	for index in MODULAR_COUNT:
		var target:=targets[index]
		hud.equip(wood_slot)
		await key(KEY_ALT,true)
		check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"holding ALT releases the mouse for block controls")
		await choose_quick(0,index+8)
		await choose_quick(2,0)
		await key(KEY_ALT,false)
		if index==2:
			await key(KEY_R,true,true);await key(KEY_R,false)
			check(game.structure_rotation==4,"Shift+R changes modular mounting direction")
			await key(KEY_R,true);await key(KEY_R,false)
			check(game.structure_rotation==5 and quick_options()[2].selected==5,"R turns within the mount and synchronizes the visible panel")
			await choose_quick(2,0)
		check(quick_options()[0].selected==index+8 and quick_options()[2].item_count==24,"quick panel stays synchronized and exposes all modular orientations")
		check(game.structure_shape==index+9 and game.structure_material==1,"normal player ALT selection reaches modular shape %d"%(index+9))
		game.player.position=Vector3(target)+Vector3(.5,0,3)
		game.camera.global_position=Vector3(target)+Vector3(.5,1.8,2.2)
		game.camera.look_at(Vector3(target)+Vector3(.5,0,.5))
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		deadline=Time.get_ticks_msec()+12000
		var hit:Dictionary=game._structure_target(false)
		while not hit.get("placement_ok",false) and Time.get_ticks_msec()<deadline:
			await process_frame;hit=game._structure_target(false)
		check(hit.get("placement_ok",false) and hit.get("target")==target,"actual targeting accepts grid cell for shape %d"%(index+9))
		game._prefab_preview_timer=0;game._update_prefab_preview(0)
		check(game.shape_preview.visible and game.shape_preview.mesh==blocks.preview_mesh(index+9,0),"ghost matches native selected shape")
		await click(MOUSE_BUTTON_RIGHT)
		check(blocks.get_cell(target)==blocks.encode_block(index+9,0,1),"RMB places shape %d as an independent native cell"%(index+9))
		if index==2:
			game.camera.global_position=Vector3(target)+Vector3(1.8,1.5,2.8)
			game.camera.look_at(Vector3(target)+Vector3(.45,.5,.5))
			for frame in 20:await process_frame
			await picture("quarter_arch.png")
	check(material_count(hud.inventory,102)==start_material-MODULAR_COUNT,"modular placements each charge exactly one wood block")
	var saved:PackedByteArray=game.structures.capture_storage_snapshot()
	check(not saved.is_empty(),"real structures storage captures new shapes")
	FileAccess.open(output.path_join("blocks.tfbl"),FileAccess.WRITE).store_buffer(blocks.capture_snapshot())
	var placed_records:Array=[]
	for target in targets:placed_records.append([target.x,target.y,target.z,blocks.get_cell(target)])
	FileAccess.open(output.path_join("placed_records.json"),FileAccess.WRITE).store_string(JSON.stringify(placed_records))
	game.camera.global_position=Vector3(base)+Vector3(14,8,25)
	game.camera.look_at(Vector3(base)+Vector3(14,1,.5))
	for frame in 30:await process_frame
	await picture("placed_shapes.png")
	var points:Array[Vector3]=[Vector3(.5,.06,.5),Vector3(.06,.5,.5),Vector3(.66,.66,.5),Vector3(.5,.25,.5),Vector3(.8,.6,.8),Vector3(.8,.6,.2),Vector3(.5,.45,.5),Vector3(.04,.96,.5),Vector3(.5,.44,.5),Vector3(.04,.96,.5)]
	for index in MODULAR_COUNT:
		var target:=targets[index]
		hud.equip(axe_slot)
		game.player.position=Vector3(target)+Vector3(.5,0,3)
		game.camera.global_position=Vector3(target)+points[index]+Vector3(0,0,2)
		game.camera.look_at(Vector3(target)+points[index])
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
		var selected:Dictionary=game.world_attack.target()
		check(selected.get("kind")=="block" and selected.get("cell")==target and selected.get("material")=="wood","tool targets exact modular block and material %d"%(index+9))
		var wear:int=hud.inventory.snapshot().slots[axe_slot].wear
		game.world_attack.next_attack=0
		check(await swing.strike(game),"animated axe contact damages modular block")
		check(blocks.get_cell(target)!=0 and hud.damage_feedback.remaining==30 and hud.inventory.snapshot().slots[axe_slot].wear==wear+1,"first strike preserves cell, shares durability and wears tool once")
		game.world_attack.next_attack=0
		check(await swing.strike(game) and blocks.get_cell(target)==0,"second axe contact destroys only selected block")
		check(blocks.get_cell(target-Vector3i.UP)==65,"support block survives destruction")
	check(game.structures.restore_storage_snapshot(saved),"native structures storage restores destroyed modular blocks")
	for index in MODULAR_COUNT:
		check(blocks.get_cell(targets[index])==blocks.encode_block(index+9,0,1),"restored shape identity and material %d"%(index+9))
	check(game.persistence._capture().sections.has("structures"),"normal world persistence includes integrated structures")
	var path:=output.path_join("structures.tfbs")
	FileAccess.open(path,FileAccess.WRITE).store_buffer(saved)
	await finish()

func finish() -> void:
	game.shutdown_requested=true
	await game.terrain.shutdown_after_edits()
	game.free()
	await process_frame
	for name:String in pictures:
		check(pictures[name].save_png(output.path_join(name))==OK,"retained actual-world image "+name)
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("MODULAR_BLOCKS_WORLD checks=",checks," failures=",failures)
	quit(1 if failures else 0)
