extends SceneTree

const Workshop = preload("res://addons/structures/workshop_catalog.gd")
const Market = preload("res://addons/structures/central_market.gd")
const Plans = preload("res://addons/world_runtime/world_generation_plan.gd")
var checks := 0
var failures := 0
var reference := "res://reviews/modular_buildings/baked/shop_roof_b2.tres"
var output := "res://reports/approved_shop_generation"

func _initialize() -> void:run.call_deferred()

func check(accepted: bool, label: String) -> void:
	checks+=1
	if not accepted:failures+=1
	print("PASS " if accepted else "FAIL ",label)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--approved-reference="):reference=argument.trim_prefix("--approved-reference=")
		if argument.begins_with("--shop-output="):output=argument.trim_prefix("--shop-output=")
	DirAccess.make_dir_recursive_absolute(output)
	var approved: Resource=Workshop.village_shop()
	var reviewed: Resource=load(reference)
	check(approved!=null and reviewed!=null,"production B2 and exact user-reviewed reference load")
	if approved==null or reviewed==null:quit(1);return
	check(approved.get_records()==reviewed.get_records() and approved.get_model_attachments()==reviewed.get_model_attachments(),"all approved B2 records and attached objects copied exactly")
	check(approved.get_cell_count()==1028 and approved.get_meta("approved_for_default",false) and approved.get_meta("approved_revision","")=="B2 R2" and not approved.get_meta("review_only",false),"specific 1028-block B2 revision is approved for production")
	check(approved.resource_name=="Village general store","existing generation lookup name remains stable")
	var legacy: Resource=Workshop.legacy_village_shop()
	check(legacy.get_records()!=approved.get_records() and legacy.get_model_attachments()==approved.get_model_attachments(),"legacy B0 remains distinct with unchanged attached objects")
	for rotation in 4:
		check(approved.foundation_samples(Vector3i.ZERO,rotation,0)==legacy.foundation_samples(Vector3i.ZERO,rotation,0),"unchanged B0 foundation samples rotation "+str(rotation))
	var independent: Resource=Workshop.village_shop()
	check(independent!=approved and independent.configure(PackedInt32Array([0,0,0,1])) and Workshop.village_shop().get_records()==reviewed.get_records(),"mutating one B2 resource cannot corrupt future shops")
	var lots: Array=Market.recipe(Vector3.ZERO)
	var hipped: Resource=Workshop.hipped_shop()
	check(lots.size()==8 and lots[1].asset.get_records()==reviewed.get_records() and lots[6].asset.get_records()==hipped.get_records(),"market retains gabled B2 and adds exact hipped B1 in the other shop lot")
	var cached: Dictionary=Plans.without_assets({"plan":{},"market":{"center":Vector3.ZERO,"lots":lots}})
	check(Plans.attach_assets(cached) and cached.market.lots[1].asset.get_records()==reviewed.get_records() and cached.market.lots[6].asset.get_records()==hipped.get_records(),"cached market plans reconstruct both approved shops")
	check(Plans.VERSION>=5 and preload("res://addons/world_runtime/custom_world_plan.gd").VERSION>=5,"both derived caches invalidate pre-shop-approval plans")
	var structures: Node3D=preload("res://addons/structures/structures_world.gd").new()
	root.add_child(structures)
	check(structures.prepare(),"native compound structures store prepares")
	preload("res://addons/structures/furniture_catalog.gd").register(structures)
	preload("res://addons/structures/storage_catalog.gd").register(structures)
	preload("res://addons/structures/door_catalog.gd").register(structures)
	preload("res://addons/structures/window_catalog.gd").register(structures)
	preload("res://addons/structures/ladder_catalog.gd").register(structures)
	var transaction: RefCounted=ClassDB.instantiate("NativePrefabPlacement")
	for lot: Dictionary in lots:
		var placed: Dictionary=transaction.place(structures.blocks,lot.asset,lot.origin,lot.rotation,structures.model_collections(),[])
		check(placed.get("ok",false),"actual native compound placement "+lot.label)
	var snapshot: PackedByteArray=structures.capture_storage_snapshot()
	var snapshot_path:=output.path_join("market.tfbs")
	if "--restore-shops" in OS.get_cmdline_user_args():
		var saved:=FileAccess.get_file_as_bytes(snapshot_path)
		check(not saved.is_empty() and structures.restore_storage_snapshot(saved) and structures.capture_storage_snapshot()==saved,"fresh process restores exact generated market blocks and attachments")
	else:
		FileAccess.open(snapshot_path,FileAccess.WRITE).store_buffer(snapshot)
		var roof_cell: Vector3i=lots[1].origin+Vector3i(-3,9,9)
		check(structures.blocks.get_cell(roof_cell)!=0 and structures.blocks.set_cells(PackedInt32Array([roof_cell.x,roof_cell.y,roof_cell.z,0])),"approved B2 roof remains locally destructible")
		check(structures.restore_storage_snapshot(snapshot) and structures.capture_storage_snapshot()==snapshot,"both approved shops and attachments survive exact compound restore")
	var old_blocks: Node3D=ClassDB.instantiate("NativeBlockWorld")
	check(old_blocks.set_cells(legacy.get_records()),"legacy saved shop block store still loads")
	var old_snapshot: PackedByteArray=old_blocks.capture_snapshot()
	check(old_blocks.set_cells(approved.get_records()) and old_blocks.restore_snapshot(old_snapshot) and old_blocks.capture_snapshot()==old_snapshot,"new default never rewrites restored legacy shop cells")
	old_blocks.free();structures.free();await process_frame
	print("APPROVED_SHOP_GENERATION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
