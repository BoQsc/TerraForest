extends SceneTree

var game:Node
var checks:=0
var failures:=0
var folder:="res://reports/developer_shapes"
func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->bool:
	checks+=1;print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
	return condition
func frames(count:int=3)->void:
	for frame in count:await process_frame
func until(predicate:Callable,seconds:int)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func amount(item:int)->int:
	var total:=0
	for row:Dictionary in game.player_hud.inventory.snapshot().slots:
		if row.item==item:total+=row.count
	return total
func key(code:int,unicode_value:int=0)->void:
	for pressed:bool in [true,false]:
		var event:=InputEventKey.new();event.physical_keycode=code;event.keycode=code;event.unicode=unicode_value;event.pressed=pressed
		Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
func click(button:Button)->void:
	for pressed:bool in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.position=button.get_global_rect().get_center();event.global_position=event.position
		Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
func capture(label:String)->void:
	await frames();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label+".png"))==OK,"capture "+label)
func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--navigation-evidence="):folder=argument.trim_prefix("--navigation-evidence=")
	folder=ProjectSettings.globalize_path(folder);DirAccess.make_dir_recursive_absolute(folder)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";game.first_person_view.settings_path="";root.add_child(game)
	if not check(await until(func():return not game.loading_active and not game.needs_floor_spawn and game.session_menu.ready_to_dock,65),"temporary world and native construction become ready"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.zombies.population_enabled=false;game.zombies.clear()
	var menu:CanvasLayer=game.session_menu;var shapes:RefCounted=menu.dev_shapes;var hud:CanvasLayer=game.player_hud;var inventory:RefCounted=hud.inventory
	check(menu.navigation.has("Dev Shapes") and menu.pages.has("Dev Shapes") and not menu.tool_workspace.pages.has("Dev Shapes"),"shape catalog has its own ESC page beside bag/spawner, not an Alt workspace")
	menu.show_page("Dev Shapes");await frames()
	check(shapes.entries.size()==game.ShapeCatalog.NAMES.size() and shapes.entries.size()==18,"gallery enumerates the entire integrated native shape catalog")
	var complete:=true;var atlas:Texture2D=shapes.entries[1].icon.atlas
	for shape:int in shapes.entries:
		var icon:AtlasTexture=shapes.entries[shape].icon
		complete=complete and icon!=null and icon.atlas==atlas and icon.get_image().get_used_rect().size!=Vector2i.ZERO
	check(complete and menu.pages["Dev Shapes"].find_children("*","SubViewport",true,false).is_empty(),"all native silhouettes use nonempty shared baked images, with no live icon viewports")
	shapes.search.grab_focus();await key(KEY_M,109);await key(KEY_QUOTELEFT,96)
	check(shapes.search.text=="m`" and menu.current_page=="Dev Shapes" and not menu.developer and not game.world_map.opened,"search consumes map/developer shortcuts without changing play mode")
	shapes.search.text="  ARCH ";shapes.filter_shapes()
	check(shapes.entries[11].visible and not shapes.entries[1].visible and not shapes.empty.visible,"trimmed case-insensitive search finds the separate quarter-arch piece")
	shapes.category.select(3);shapes.filter_shapes();check(shapes.empty.visible,"category and name filters combine with a visible empty state")
	shapes.search.clear();shapes.filter_shapes()
	check(shapes.entries.values().filter(func(tile):return tile.visible).size()==7 and shapes.entries[18].visible,"roof category includes all seven current roof/seam pieces")
	shapes.category.select(0);shapes.search.text="18";shapes.filter_shapes()
	check(shapes.entries[18].visible and shapes.entries.values().filter(func(tile):return tile.visible).size()==1,"native shape IDs are searchable")
	shapes.search.clear();shapes.filter_shapes();shapes.search.release_focus();await capture("catalog_top")
	menu.scroll.scroll_vertical=1000;await capture("catalog_roofs");menu.scroll.scroll_vertical=0;await frames()
	var base:=Vector3i(game.player.global_position.floor())+Vector3i(0,8,0);var target:=base+Vector3i.UP
	check(game.structures.blocks.set_cells(PackedInt32Array([base.x,base.y,base.z,game.structures.blocks.encode_block(1,0,2)])),"isolated one-cell support is authored above terrain without changing any save")
	game.structures.blocks.set_focus(Vector3(base));await frames(10)
	game.camera.global_position=Vector3(base)+Vector3(.5,2.5,.5);game.camera.look_at(Vector3(base)+Vector3(.5,.5,.5),Vector3.FORWARD)
	shapes.material.select(2);shapes.count.value=5;var stock:=amount(103)
	await click(shapes.entries[4])
	if not check(not menu.opened and not menu.developer and game.structure_mode and game.structure_shape==4 and game.structure_material==2 and game.equipped_tool==103 and amount(103)==stock+5,"real tile click grants concrete and equips its slope immediately in gameplay mode"):await finish();return
	var hit:Dictionary=game._structure_target(false)
	if not check(not hit.is_empty() and hit.target==target,"normal player building ray selects the support's adjacent grid cell"):await finish();return
	var all_shapes:=true;var all_costs:=true;var all_destroyed:=true
	for shape in range(1,game.ShapeCatalog.NAMES.size()+1):
		menu.show_page("Dev Shapes");shapes.material.select(2);shapes.count.value=5;shapes.entries[shape].pressed.emit()
		all_shapes=all_shapes and not menu.opened and game.structure_shape==shape and game.structure_prefab_index==-1 and game.structure_rotation==0 and not menu.developer
		var before:=amount(103);game._edit_structure(false)
		var expected:int=game.structures.blocks.encode_block(shape,0,2)
		all_shapes=all_shapes and game.structures.blocks.get_cell(target)==expected
		all_costs=all_costs and amount(103)==before-1
		hud.equip_item(1)
		var block:Dictionary={"kind":"block","key":game.world_attack.block_key(target),"health":120,"material":"stone","name":"Shape block","cell":target}
		for strike in 4:all_destroyed=game.world_attack.apply_target(block) and all_destroyed
		all_destroyed=all_destroyed and game.structures.blocks.get_cell(target)==0
		await frames(3)
	check(all_shapes,"all 18 gallery choices place their actual native single-cell geometry, not prefabs or models")
	check(all_costs,"each selected shape uses exactly one ordinary material per accepted gameplay placement")
	check(all_destroyed,"all 18 placed pieces can be independently destroyed through normal block health/removal")
	hud.equip_item(103)
	check(game.structure_shape==18 and game.construction_palette.shape.selected==17 and game.construction_palette.rotation_choice.item_count==24,"returning from a weapon restores the chosen material's shape and modular rotations")
	for material in 4:
		menu.show_page("Dev Shapes");shapes.material.select(material);shapes.count.value=3;var before:=amount(101+material);shapes.entries[10+material%2].pressed.emit()
		check(amount(101+material)==before+3 and game.equipped_tool==101+material and game.structure_material==material and game.structure_shape==10+material%2,"shape selection grants and equips correct material "+str(material))
	var original:PackedByteArray=inventory.capture_storage_snapshot();var full:Dictionary=inventory.snapshot()
	for row:Dictionary in full.slots:row.item=101;row.count=999;row.wear=0;row.water_ml=0
	inventory.restore(full,inventory.snapshot().revision);hud.refresh();menu.show_page("Dev Shapes");shapes.material.select(2);shapes.count.value=1
	var saved:PackedByteArray=inventory.capture_storage_snapshot();var revision:int=inventory.snapshot().revision;var old_shape:int=game.structure_shape
	shapes.entries[11].pressed.emit()
	check(menu.opened and inventory.capture_storage_snapshot()==saved and inventory.snapshot().revision==revision and game.structure_shape==old_shape and menu.message.text.contains("Nothing was added"),"full bag leaves inventory, revision, selected shape and menu unchanged")
	shapes.use_shape(0);shapes.use_shape(19);check(inventory.capture_storage_snapshot()==saved and game.structure_shape==old_shape,"invalid shapes cannot grant materials or change tools")
	inventory.restore_storage_snapshot(original);hud.refresh();menu.toggle_developer();menu.show_page("Dev Shapes");shapes.material.select(1);shapes.count.value=3;stock=amount(102);shapes.entries[11].pressed.emit()
	check(menu.developer and not menu.opened and hud.developer_slot==3 and game.editor_tool_active and game.structure_shape==11 and game.structure_material==1 and amount(102)==stock+3,"same gallery equips the development building tool without leaving developer mode")
	stock=amount(102);game._edit_structure(false)
	check(game.structures.blocks.get_cell(target)==game.structures.blocks.encode_block(11,0,1) and amount(102)==stock,"developer placement retains free native authoring, not gameplay costs")
	game.structures.blocks.set_cells(PackedInt32Array([target.x,target.y,target.z,0]));menu.show_page("Dev Shapes");await key(KEY_ESCAPE)
	check(not menu.visible_ui() and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"ESC closes the shape browser directly back to play")
	await finish()
func finish()->void:
	if game!=null:game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await frames(2)
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("DEVELOPER_SHAPES checks=",checks," failures=",failures);quit(1 if failures else 0)
