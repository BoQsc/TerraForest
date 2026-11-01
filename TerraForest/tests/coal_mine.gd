# SPDX-License-Identifier: 0BSD
extends "res://tests/exploration_layouts.gd"
const Rails=preload("res://addons/structures/mine_rail_catalog.gd")
func run()->void:
	core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,29]))
	var layouts:=Layouts.load_catalog();var layout:Dictionary=layouts.filter(func(row:Dictionary):return row.id=="coal_mine")[0]
	var planned:Dictionary=core.plan_exploration_sites(layouts,[],[])
	var site:Dictionary=planned.sites.filter(func(row:Dictionary):return row.id=="coal_mine")[0]
	var anchors:=Layouts.sleepers(layout,site.origin,site.rotation)
	check(anchors.filter(func(row:Dictionary):return (int(row.key)&(1<<43))!=0).size()==10,"deep loading station owns exactly ten stable zombie identities")
	check(anchors.size()==13,"three smaller encounters supplement the ten station residents")
	var world:=preload("res://addons/structures/structures_world.gd").new();root.add_child(world)
	check(Rails.register(world).size()==5,"five modular rail models register with native collision")
	preload("res://addons/structures/storage_catalog.gd").register(world)
	preload("res://addons/structures/door_catalog.gd").register(world)
	preload("res://addons/exploration/coal_resource.gd").register(world)
	# Two eighth bends must connect as the quarter-turn module does, and must
	# actually publish together through native collision validation.
	var eighth:=Rails.mesh("eighth");var quarter:=Rails.mesh("curve")
	var second:=Transform3D(Basis(Vector3.UP,-PI*.25),eighth.get_meta("finish"))
	check((second*Vector3(eighth.get_meta("finish"))).distance_to(quarter.get_meta("finish"))<.001,"two 45-degree bends meet the 90-degree endpoint")
	var pair:Resource=ClassDB.instantiate("NativeBlockPrefab");pair.configure(PackedInt32Array())
	pair.configure_model_attachments([{"model":Rails.key("eighth"),"transform":Transform3D.IDENTITY},{"model":Rails.key("eighth"),"transform":second}])
	pair.configure_attachment_envelope(eighth.get_aabb().merge(second*eighth.get_aabb()).grow(.01))
	var joint:Dictionary=ClassDB.instantiate("NativePrefabPlacement").place(world.blocks,pair,Vector3i(300,40,300),0,world.model_collections(),[])
	check(joint.get("ok",false),"joined 45-degree modular bends publish: "+str(joint.get("reason","ok")))
	var asset:=Layouts.prefab(layout);check(asset!=null,"coal mine composes grid building and model attachments")
	if asset==null:world.free();quit(1);return
	var cuts:=Layouts.segments(layout,site.origin,site.rotation);cuts.push_front(site.approach)
	for packet:PackedByteArray in Earthworks.packets(cuts):check(Codec.reply_ok(core.execute(packet)),"native mountain excavation")
	var placer=ClassDB.instantiate("NativePrefabPlacement")
	var attachments:Array=asset.get_model_attachments()
	# Diagnose real transformed compound proxies, including joins, not diagram counts.
	var boxes:Array=[]
	for index in attachments.size():
		var item:Dictionary=attachments[index];var mesh:Mesh
		if item.model=="storage/wooden_chest/v1":mesh=load("res://addons/structures/prefabs/storage_chest_model.tres")
		else:mesh=preload("res://addons/exploration/coal_mine.gd").mesh_for(item.model)
		var parts:Array=mesh.get_meta("collision_parts",[mesh.get_aabb()])
		for bounds:AABB in parts:
			var actual:AABB=item.transform*bounds
			for previous:Dictionary in boxes:
				if previous.index!=index and previous.bounds.grow(-.001).intersects(actual.grow(-.001)):print("COAL_OVERLAP ",previous.index," ",index," ",actual," ",previous.bounds)
			boxes.append({"index":index,"bounds":actual})
		var single:Resource=ClassDB.instantiate("NativeBlockPrefab");single.configure(PackedInt32Array());single.configure_model_attachments([item]);single.configure_attachment_envelope(item.transform*mesh.get_aabb().grow(.05))
		var samples:Dictionary=placer.ground_model_samples(single,site.origin,site.rotation,world.model_collections())
		if not samples.get("ok",false):print("COAL_SAMPLES ",index," ",samples)
		else:
			for point:Vector3 in samples.clearance:
				if density(point)<0:print("COAL_TERRAIN ",index," ",item.model," point=",point," density=",density(point));break
	var field:=preload("res://tests/terrain_block_contract.gd").Field.new();root.add_child(field);field.core=core
	field.validator=preload("res://addons/structures/foundation_check.gd").new();field.density_revision=core.execute(Codec.command(0)).decode_u32(12)
	check(field.validator.begin(field,asset,site.origin,site.rotation),"shared station support check begins")
	while field.validator.status=="checking":field.validator.tick(field);await process_frame
	check(field.validator.status=="supported","station building support and exposed surfaces: "+field.validator.status)
	check(field.validator.begin_ground_models(field,asset,site.origin,site.rotation,world.model_collections()),"shared model support check begins")
	while field.validator.status=="checking":field.validator.tick(field);await process_frame
	check(field.validator.status=="supported","all props and rail envelopes clear mountain: "+field.validator.status)
	var placed:Dictionary=placer.place(world.blocks,asset,site.origin,site.rotation,world.model_collections(),[])
	check(placed.get("ok",false),"atomic native blocks/models publication: "+str(placed.get("reason","ok")))
	if placed.get("ok",false):
		for part:String in Rails.PARTS:
			var collection:Node=world.model(Rails.key(part));var snapshot:PackedByteArray=collection.capture_snapshot()
			check(collection.restore_snapshot(snapshot) and collection.capture_snapshot()==snapshot,"exact rail identity restoration: "+part)
	var population=ClassDB.instantiate("NativeZombiePopulation");population.initialize(1703,Vector3.ZERO)
	check(population.register_sleepers(anchors).get("ok",false),"all thirteen keyed sleepers publish to normal population")
	var saved:PackedByteArray=population.capture_snapshot();check(population.restore_snapshot(saved) and saved==population.capture_snapshot(),"station residents and sleep state round-trip exactly")
	var awareness=ClassDB.instantiate("NativeZombieAwareness")
	check(awareness.configure(16,1703),"native bounded awareness admits the entire station")
	var oversized=ClassDB.instantiate("NativeZombieAwareness");check(not oversized.configure(17,1703),"awareness rejects capacity above the explicit encounter cap")
	field.free();world.free();await process_frame
	print("COAL_MINE checks=",checks," failures=",failures);quit(1 if failures else 0)
