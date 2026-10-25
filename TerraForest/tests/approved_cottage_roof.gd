extends SceneTree

const Furniture = preload("res://addons/structures/furniture_catalog.gd")
const Lots = preload("res://addons/structures/northern_lots.gd")
const Market = preload("res://addons/structures/central_market.gd")
const Plans = preload("res://addons/world_runtime/world_generation_plan.gd")
var checks := 0
var failures := 0
var reference := "res://reviews/modular_buildings/baked/cottage_roof_a2.tres"

func _initialize() -> void:run.call_deferred()

func check(accepted: bool, label: String) -> void:
	checks+=1
	if not accepted:failures+=1
	print("PASS " if accepted else "FAIL ",label)

func verify_lots(lots: Array, expected: Resource, count: int) -> void:
	var found := 0
	var exact := true
	for lot: Dictionary in lots:
		if lot.asset.resource_name!=expected.resource_name:continue
		found+=1
		exact=exact and lot.asset.get_records()==expected.get_records() and lot.asset.get_model_attachments()==expected.get_model_attachments()
	check(found==count and exact,"generation recipe uses exact approved cottages: "+str(count))

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--approved-reference="):reference=argument.trim_prefix("--approved-reference=")
	var approved: Resource=Furniture.enclosed_cottage()
	var reviewed: Resource=load(reference)
	check(approved!=null and reviewed!=null,"production cottage and user-reviewed reference load")
	if approved==null or reviewed==null:quit(1);return
	check(approved.get_records()==reviewed.get_records() and approved.get_model_attachments()==reviewed.get_model_attachments(),"production exactly matches the 555 approved blocks and 13 attached objects")
	check(approved.get_cell_count()==555 and approved.get_model_attachments().size()==13,"approved assembly counts")
	check(approved.get_meta("approved_for_default",false) and approved.get_meta("approved_revision","")=="A2 R2" and not approved.get_meta("review_only",false),"production records specific default approval")
	check(approved.resource_name=="Furnished cottage with door and windows","preset lookup name remains stable")
	var legacy: Resource=Furniture.legacy_enclosed_cottage()
	check(legacy.get_records()!=approved.get_records() and legacy.get_model_attachments()==approved.get_model_attachments(),"historical A0 stays separate with identical attached objects")
	for rotation in 4:
		check(approved.placement_bounds(Vector3i.ZERO,rotation)==legacy.placement_bounds(Vector3i.ZERO,rotation),"unchanged placement envelope rotation "+str(rotation))
		check(approved.foundation_samples(Vector3i.ZERO,rotation,0)==legacy.foundation_samples(Vector3i.ZERO,rotation,0),"unchanged foundation samples rotation "+str(rotation))
	var independent: Resource=Furniture.enclosed_cottage()
	check(independent!=approved and independent.configure(PackedInt32Array([0,0,0,1])),"callers receive independent native prefab resources")
	check(approved.get_records()==reviewed.get_records() and Furniture.enclosed_cottage().get_records()==reviewed.get_records(),"mutating one instance cannot corrupt future cottages")
	var old_world: Node3D=ClassDB.instantiate("NativeBlockWorld")
	check(old_world.set_cells(legacy.get_records()),"legacy cottage block store still loads")
	var saved: PackedByteArray=old_world.capture_snapshot()
	var approved_blocks: Resource=ClassDB.instantiate("NativeBlockPrefab")
	check(approved_blocks.configure(approved.get_records()) and old_world.place_prefab(approved_blocks,Vector3i(32,0,0),0),"old and approved roof cells coexist")
	check(old_world.restore_snapshot(saved) and old_world.capture_snapshot()==saved,"saved legacy cells restore byte-for-byte, without roof migration")
	old_world.free()
	var neighborhood: Array=Lots.recipe(Vector3.ZERO)
	var market: Array=Market.recipe(Vector3.ZERO)
	verify_lots(neighborhood,approved,4)
	verify_lots(market,approved,3)
	var cached: Dictionary=Plans.without_assets({"plan":{"center":Vector3.ZERO,"lots":neighborhood},"market":{"center":Vector3.ZERO,"lots":market}})
	check(Plans.attach_assets(cached),"cached plans reconstruct production prefabs")
	verify_lots(cached.plan.lots,approved,4)
	verify_lots(cached.market.lots,approved,3)
	check(Plans.VERSION>=4 and preload("res://addons/world_runtime/custom_world_plan.gd").VERSION>=4,"both derived placement caches invalidate pre-approval recipes")
	var game: Node3D=load("res://demo/world.tscn").instantiate()
	game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"actual temporary gameplay world finishes loading")
	if not game.loading_active:
		game.set_physics_process(false);game.app_focused=true;game.session_menu.set_open(false)
		var asset: Resource=game.structure_prefabs[6]
		check(asset.get_records()==reviewed.get_records() and asset.get_model_attachments()==reviewed.get_model_attachments(),"existing enclosed-cottage palette index now uses exact approved A2")
		check(game._set_player_tool_mode(true,false,-1),"normal developer building tool activates")
		var palette: Node=game.construction_palette
		palette.prefab.select(7);palette.prefab.item_selected.emit(7)
		check(game.structure_prefab_index==6 and palette.prefab.get_item_text(7)==approved.resource_name,"normal construction UI selects the approved cottage")
		var transaction: RefCounted=ClassDB.instantiate("NativePrefabPlacement")
		var origin:=Vector3i(128,256,128)
		var placed: Dictionary=transaction.place(game.structures.blocks,asset,origin,0,game.structures.model_collections(),[])
		check(placed.get("ok",false),"approved cottage places through actual gameplay native compound transaction")
		if placed.get("ok",false):
			var snapshot: PackedByteArray=game.structures.capture_storage_snapshot()
			var roof_cell:=origin+Vector3i(-2,8,6)
			var neighbor:=roof_cell+Vector3i(0,0,-1)
			var neighbor_word: int=game.structures.blocks.get_cell(neighbor)
			check(game.structures.blocks.get_cell(roof_cell)!=0 and game.structures.blocks.set_cells(PackedInt32Array([roof_cell.x,roof_cell.y,roof_cell.z,0])) and game.structures.blocks.get_cell(neighbor)==neighbor_word,"one approved roof block removes without deleting its neighbor")
			check(game.structures.restore_storage_snapshot(snapshot) and game.structures.capture_storage_snapshot()==snapshot,"actual gameplay compound save restores approved roof and all attachments exactly")
	game.shutdown_requested=true
	await game.terrain.shutdown_after_edits()
	game.free();await process_frame
	print("APPROVED_COTTAGE_ROOF checks=",checks," failures=",failures)
	quit(1 if failures else 0)
