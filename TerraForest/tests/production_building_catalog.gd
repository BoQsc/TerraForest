# SPDX-License-Identifier: 0BSD
extends SceneTree
const Civic=preload("res://addons/structures/civic_catalog.gd")
const E2=preload("res://addons/structures/expansion_catalog.gd")
const Furniture=preload("res://addons/structures/furniture_catalog.gd")
const Shops=preload("res://addons/structures/workshop_catalog.gd")
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Custom=preload("res://addons/world_runtime/custom_world_plan.gd")
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	var public_assets:Array=[]
	for index in Civic.IDS.size():public_assets.append(Civic.asset(index))
	public_assets.append_array([Furniture.enclosed_cottage(),Shops.village_shop(),Shops.hipped_shop(),Furniture.large_house()])
	for index in E2.IDS.size():
		var actual:Resource=public_assets[index]
		var original:Resource=load("res://addons/structures/prefabs/expansion_"+E2.IDS[index]+"_e2.tres")
		check(actual!=null and actual.get_records()==original.get_records() and actual.get_model_attachments()==original.get_model_attachments(),"normal catalog uses exact approved cells and attachments: "+E2.IDS[index])
		check(not actual.get_meta("review_only",true) and actual.get_meta("approved_date","")=="2026-11-01","normal catalog exposes approved revision: "+E2.IDS[index])
	var fingerprints:Dictionary={}
	for index in E2.IDS.size():fingerprints[E2.IDS[index]]=Custom.prefab_fingerprint(public_assets[index])
	print("PRODUCTION_PREFAB_FINGERPRINTS ",JSON.stringify(fingerprints))
	var fingerprint_asset:Resource=public_assets[0].duplicate()
	var original_fingerprint:=Custom.prefab_fingerprint(fingerprint_asset)
	check(original_fingerprint.length()==64 and original_fingerprint==Custom.prefab_fingerprint(public_assets[0]),"loaded-content fingerprint is stable across resource copies")
	var changed_records:PackedInt32Array=fingerprint_asset.get_records();changed_records.resize(changed_records.size()-4);fingerprint_asset.set_records(changed_records)
	check(Custom.prefab_fingerprint(fingerprint_asset)!=original_fingerprint,"cell edits invalidate placement cache")
	fingerprint_asset=public_assets[0].duplicate();fingerprint_asset.set_meta("site_surface_offset",int(fingerprint_asset.get_meta("site_surface_offset",0))+1)
	check(Custom.prefab_fingerprint(fingerprint_asset)!=original_fingerprint,"planning metadata invalidates placement cache")
	fingerprint_asset=public_assets[0].duplicate();var attachments:Array=fingerprint_asset.get_model_attachments();attachments.pop_back();fingerprint_asset.set_model_attachments(attachments)
	check(Custom.prefab_fingerprint(fingerprint_asset)!=original_fingerprint,"attachment edits invalidate placement cache")
	check(Furniture.enclosed_cottage().resource_name=="Furnished cottage with door and windows","existing construction presets retain cottage identity")
	var cases:Array=[Recipe.DEFAULTS.duplicate()]
	if "--all-recipes" in OS.get_cmdline_user_args():
		cases.clear()
		for style:Dictionary in preload("res://demo/world_creation_panel.gd").STYLES:
			var values:Array=style.values
			cases.append({"biome":values[0],"settlements":values[1]+1,"districts":values[2]+1,"network":values[3],"trails":values[4],"road_grid":3,"material_veins":1})
	for settings:Dictionary in cases:
		var worker:=Thread.new();worker.start(Plan.build.bind(1703,29,true,true,"user://generation_plans",settings))
		while worker.is_alive():await process_frame
		var result:Dictionary=worker.wait_to_finish()
		check(result.get("ok",false),"normal recipe fits: "+str(settings)+" / "+str(result.get("reason","ok")))
		if not result.get("ok",false):continue
		var civic_sites:Array=result.sites.filter(func(site:Dictionary):return site.recipe_kind=="civic")
		check(civic_sites.size()==1 and civic_sites[0].lots.size()==5,"one civic district includes all five civic buildings")
		var merchants:Array=result.navigation.places.filter(func(place:Dictionary):return int(place.id)==Civic.MERCHANT_PLACE)
		check(merchants.size()==1,"each normal recipe provides exactly one resident trader destination")
		check(civic_sites[0].lots.all(func(lot:Dictionary):return lot.asset.get_meta("expansion_revision","")=="E2"),"generation selects E2 before fitting terrain and basements")
		var warm:=Plan.build(1703,29,true,true,"user://generation_plans",settings)
		check(warm.cache_hit and warm.plan_digest==result.plan_digest and warm.sites[0].lots[0].asset.get_records()==result.sites[0].lots[0].asset.get_records(),"cached preview reconstructs the same approved prefab content")
	print("PRODUCTION_BUILDING_CATALOG checks=",checks," failures=",failures)
	quit(1 if failures else 0)
