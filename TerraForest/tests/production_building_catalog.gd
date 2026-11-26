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
		var inherited:Array=original.get_model_attachments()
		check(actual!=null and actual.get_records()==original.get_records() and actual.get_model_attachments().slice(0,inherited.size())==inherited,"normal catalog retains approved cells and original attachments: "+E2.IDS[index])
		var envelope:=true
		for turn in 4:envelope=envelope and actual.placement_bounds(Vector3i.ZERO,turn)==original.placement_bounds(Vector3i.ZERO,turn) and actual.foundation_samples(Vector3i.ZERO,turn,0)==original.foundation_samples(Vector3i.ZERO,turn,0)
		check(envelope,"furnishing retains every terrain-planning footprint: "+E2.IDS[index])
		if E2.IDS[index] in ["cottage_a2","house_c1"]:check(actual.has_meta("homestead_furnishings") and actual.get_model_attachments().size()>inherited.size(),"ordinary house catalog adds Homestead furnishings: "+E2.IDS[index])
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
	if "--recipes-only" in OS.get_cmdline_user_args():
		var planner=preload("res://addons/structures/terrain_lot_planner.gd")
		for recipe:Callable in [Civic.recipe,preload("res://addons/structures/city_catalog.gd").recipe,preload("res://addons/structures/northern_lots.gd").recipe,preload("res://addons/structures/central_market.gd").recipe]:
			for center:Vector3 in [Vector3(800,0,1200),Vector3(800.25,0,1200.75)]:
				var source:Array=recipe.call(center);var target:=center+Vector3(48,0,-72)
				var actual:Array=planner.translated_recipe(source,center,target);var expected:Array=recipe.call(target)
				var exact:=actual.size()==expected.size()
				for index in mini(actual.size(),expected.size()):
					exact=exact and actual[index].origin==expected[index].origin and actual[index].rotation==expected[index].rotation and actual[index].street_z==expected[index].street_z and actual[index].label==expected[index].label and Custom.prefab_fingerprint(actual[index].asset)==Custom.prefab_fingerprint(expected[index].asset)
				check(exact,"reused recipe matches fresh catalog geometry, furnishings and plot coordinates: "+str(recipe)+" / "+str(center))
		if "--recipes-only" in OS.get_cmdline_user_args():
			print("PRODUCTION_BUILDING_CATALOG checks=",checks," failures=",failures);quit(1 if failures else 0);return
	var cases:Array=[Recipe.DEFAULTS.duplicate()]
	if "--single-district" in OS.get_cmdline_user_args():cases[0].settlements=1;cases[0].districts=1
	if "--all-recipes" in OS.get_cmdline_user_args():
		cases.clear()
		for style:Dictionary in preload("res://demo/world_creation_panel.gd").STYLES:
			var values:Array=style.values
			cases.append({"biome":values[0],"settlements":values[1]+1,"districts":values[2]+1,"network":values[3],"trails":values[4],"road_grid":3,"material_veins":1})
	for settings:Dictionary in cases:
		var progress:=preload("res://addons/world_runtime/world_plan_progress.gd").new()
		var worker:=Thread.new();var began:=Time.get_ticks_msec();var next_profile:=began;var previous:=""
		worker.start(Plan.build.bind(1703,29,true,true,"user://generation_plans",settings,progress))
		while worker.is_alive():
			if "--profile-planning" in OS.get_cmdline_user_args() and Time.get_ticks_msec()>=next_profile:
				var state:Dictionary=progress.snapshot();var activity:String=state.get("activity","")
				if activity!=previous or Time.get_ticks_msec()>=next_profile+4000:print("PLAN_PROGRESS ",Time.get_ticks_msec()-began,"ms ",JSON.stringify(state));previous=activity;next_profile=Time.get_ticks_msec()+1000
			await process_frame
		var result:Dictionary=worker.wait_to_finish()
		print("PLAN_COMPLETED milliseconds=",Time.get_ticks_msec()-began," cache_hit=",result.get("cache_hit",false)," digest=",result.get("plan_digest",""))
		check(result.get("ok",false),"normal recipe fits: "+str(settings)+" / "+str(result.get("reason","ok")))
		if not result.get("ok",false):continue
		var civic_sites:Array=result.sites.filter(func(site:Dictionary):return site.recipe_kind=="civic")
		check(civic_sites.size()==1 and civic_sites[0].lots.filter(func(lot:Dictionary):return lot.asset.has_meta("civic_id")).size()==5,"one civic district includes all five civic buildings")
		if int(settings.get("introduction",0))==1:
			check(civic_sites[0].lots.size()==6 and preload("res://addons/world_runtime/introduction_spawn.gd").select(result.sites).get("ok",false),"introduction adds the approved nearby house without replacing a civic building")
		var merchants:Array=result.navigation.places.filter(func(place:Dictionary):return int(place.id)==Civic.MERCHANT_PLACE)
		check(merchants.size()==1,"each normal recipe provides exactly one resident trader destination")
		check(civic_sites[0].lots.all(func(lot:Dictionary):return lot.asset.get_meta("expansion_revision","")=="E2"),"generation selects E2 before fitting terrain and basements")
		var warm:=Plan.build(1703,29,true,true,"user://generation_plans",settings)
		check(warm.cache_hit and warm.plan_digest==result.plan_digest and warm.sites[0].lots[0].asset.get_records()==result.sites[0].lots[0].asset.get_records(),"cached preview reconstructs the same approved prefab content")
	print("PRODUCTION_BUILDING_CATALOG checks=",checks," failures=",failures)
	quit(1 if failures else 0)
