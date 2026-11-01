# SPDX-License-Identifier: 0BSD
extends "res://tests/terrain_block_contract.gd"
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
const Civic=preload("res://addons/structures/civic_catalog.gd")
const City=preload("res://addons/structures/city_catalog.gd")
func run()->void:
	for seed_value in [1703,42]:
		for catalog in ["civic","city","neighborhood","expansion"]:
			var field:=Field.new();root.add_child(field);field.core=ClassDB.instantiate("TerrainCore")
			field.core.execute(Codec.command(6,[seed_value,25]))
			var layout:=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,16)
			var plan:Dictionary
			if catalog=="expansion":plan=Planner.locate(field.core,layout.sites[3].position,[],Rect2(),expansion_recipe,Civic.streets,Vector2(180,224))
			elif catalog=="civic":plan=Planner.locate(field.core,layout.sites[3].position,[],Rect2(),Civic.recipe,Civic.streets,Vector2(180,224))
			elif catalog=="city":plan=Planner.locate(field.core,layout.sites[3].position,[],Rect2(),City.recipe,City.streets,Vector2(180,224))
			else:plan=Planner.locate(field.core,layout.sites[3].position)
			check(plan.get("ok",false),"catalog fits full ground and approach budgets / "+catalog+" seed "+str(seed_value))
			if not plan.get("ok",false):field.free();continue
			var works:=Planner.earthworks(plan)
			var baked:Dictionary=field.core.bake_generated_earthworks(Works.packets(works.segments))
			check(baked.get("ok",false),"complete final earthworks bake / "+catalog)
			if not baked.get("ok",false):field.free();continue
			field.density_revision=baked.revision
			for lot:Dictionary in plan.lots:
				field.validator=Check.new()
				var begun:bool=field.validator.begin(field,lot.asset,lot.origin,lot.rotation)
				await drain(field)
				check(begun and field.validator.status=="supported",catalog+" / "+lot.label+" support, interior, exposed surfaces: "+field.validator.status)
			var plates:Resource=ClassDB.instantiate("NativeBlockPrefab")
			plates.configure(plan.block_paving.records);field.validator=Check.new()
			var begun:bool=field.validator.begin_surfaces_only(field,plates,Vector3i.ZERO,0)
			await drain(field)
			check(begun and field.validator.status=="supported",catalog+" / all sidewalk plate surfaces: "+field.validator.status)
			field.free()
	print("TERRAIN_BLOCK_CATALOG checks=",checks," failures=",failures);quit(1 if failures else 0)
func drain(field:Node)->void:
	var deadline:=Time.get_ticks_msec()+10000
	while field.validator.status=="checking" and Time.get_ticks_msec()<deadline:
		field.validator.tick(field);await process_frame

func expansion_recipe(center:Vector3)->Array:
	var lots:=Civic.recipe(center)
	for index in lots.size():lots[index].asset=load("res://addons/structures/prefabs/expansion_"+Civic.IDS[index]+"_e2.tres")
	return lots
