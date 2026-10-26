extends SceneTree

const Catalog=preload("res://addons/world_ecosystem/ground_catalog.gd")
const Fixtures=preload("res://tests/woodland_accents.gd")
var failures:=0
var checks:=0

func check(passed:bool,label:String)->void:
	checks+=1
	print("PASS " if passed else "FAIL ",label)
	if not passed:failures+=1

func amount(inventory:RefCounted,item:int)->int:
	var total:=0
	for slot:Dictionary in inventory.snapshot().slots:
		if slot.item==item:total+=int(slot.count)
	return total

func _initialize()->void:run.call_deferred()

func run()->void:
	for addon in ["vegetation_runtime","player_runtime"]:GDExtensionManager.load_extension("res://addons/%s/%s.gdextension"%[addon,addon])
	var cover=Fixtures.CoverStub.new()
	cover.terrain=Fixtures.TerrainStub.new();cover.add_child(cover.terrain);root.add_child(cover)
	cover.removed=ClassDB.instantiate("NativeGroundCoverState");cover.removed.bind_world(1703,1)
	cover.picker=ClassDB.instantiate("NativeGroundCoverPicker")
	for species in Catalog.COUNT:cover.batches.append(Fixtures.BatchStub.new())
	var cell:=Vector2i(30,30)
	var grass:int=cover.removed.add(2,Transform3D(Basis.IDENTITY,Vector3(970,20,972)))
	var stone:int=cover.removed.add(0,Transform3D(Basis.IDENTITY,Vector3(970,20,971.2)))
	var flower:int=cover.removed.add(3,Transform3D(Basis.IDENTITY,Vector3(970,20,970.6)))
	cover.resident[cell]=cover.removed.query(cell)
	check(cover.picker.replace_cell(cell,cover.resident[cell]),"overlapping grass, stone and flower admitted")
	var origin:=Vector3(970,20.1,973)
	var endpoint:=Vector3(970,20.1,970.5)
	var raw:Dictionary=cover.picker.pick(origin,endpoint)
	check(raw.hit and raw.id==grass,"ordinary harvesting still targets foreground grass")
	for species in Catalog.COUNT:
		check(bool(Catalog.PICKUP_SPECIES_MASK&(1<<species))==not Catalog.HARVEST_ONLY[species],"pickup mask matches species %d harvesting policy"%species)
	var selected:Dictionary=cover.picker.pick_filtered(origin,endpoint,Catalog.PICKUP_SPECIES_MASK)
	check(selected.hit and selected.id==stone,"native filtered query reaches stone through grass")
	check(selected.tested<raw.tested,"ignored grass skips proxy transforms and intersection work")
	for mask in [-1,512]:check(not cover.picker.pick_filtered(origin,endpoint,mask).hit,"invalid species mask fails closed")
	check(not cover.picker.pick_filtered(origin,endpoint,0).hit,"empty species mask selects nothing")
	var interaction=preload("res://addons/world_ecosystem/ground_interaction.gd").new()
	interaction.cover=cover;interaction.scene_ray=func(_origin:Vector3,_endpoint:Vector3)->Dictionary:return {}
	var inventory:RefCounted=ClassDB.instantiate("NativePlayerInventory")
	for item in [201,205,206]:check(inventory.register_item(item,999),"reward item %d registered"%item)
	var before:PackedByteArray=cover.removed.capture_storage_snapshot()
	check(not interaction.pickup_probe(origin,endpoint,{"position":Vector3(970,20.1,972.6)}).ok,"solid obstruction still blocks the stone")
	check(cover.removed.capture_storage_snapshot()==before,"filtered preview does not mutate vegetation")
	var collected:Dictionary=interaction.collect(origin,endpoint,inventory,true)
	check(collected.ok and collected.id==stone and amount(inventory,201)==1,"E collects the exact stone behind grass")
	check(amount(inventory,205)==0 and cover.resident[cell][2].ids.has(grass),"E leaves foreground grass intact and grants no grass")
	selected=interaction.pickup_probe(origin,endpoint)
	check(selected.ok and selected.hit.id==flower,"rarer flower becomes eligible through the same grass")
	collected=interaction.collect(origin,endpoint,inventory,true)
	check(collected.ok and collected.id==flower and amount(inventory,206)==1,"E collects the flower without harvesting grass")
	before=cover.removed.capture_storage_snapshot()
	var before_inventory:PackedByteArray=inventory.capture_storage_snapshot()
	check(not interaction.collect(origin,endpoint,inventory,true).ok,"grass alone cannot be picked up with E")
	check(cover.removed.capture_storage_snapshot()==before and inventory.capture_storage_snapshot()==before_inventory,"rejected grass pickup preserves both stores")
	collected=interaction.collect(origin,endpoint,inventory,true,null,grass)
	check(collected.ok and collected.id==grass and amount(inventory,205)==1,"completed grass harvest still grants its existing reward")
	check(not interaction.collect(origin,endpoint,inventory,true,null,grass).ok,"stale grass harvest cannot duplicate resources")
	var authored:int=cover.removed.add(2,Transform3D(Basis.IDENTITY,Vector3(970,20,972)))
	cover.resident[cell]=cover.removed.query(cell);cover.picker.replace_cell(cell,cover.resident[cell])
	before_inventory=inventory.capture_storage_snapshot()
	collected=interaction.collect(origin,endpoint,inventory,false)
	check(collected.ok and collected.id==authored and inventory.capture_storage_snapshot()==before_inventory,"developer grass removal remains available without rewards")
	cover.free()
	print("GRASS_PICKUP_PRIORITY checks=",checks," failures=",failures)
	quit(1 if failures else 0)
