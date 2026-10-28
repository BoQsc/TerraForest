extends "res://tests/approved_large_house.gd"

const City=preload("res://addons/structures/city_catalog.gd")

func run()->void:
	output="res://reports/approved_city_generation"
	DirAccess.make_dir_recursive_absolute(output)
	for index in City.IDS.size():
		var reference_asset:Resource=load("res://reviews/city_buildings/baked/"+City.IDS[index]+".tres")
		var approved:Resource=City.asset(index)
		check(approved!=null and approved.get_meta("approved_as_addition",false) and not approved.get_meta("review_only",true),"approved production identity "+City.IDS[index])
		check(approved.get_records()==reference_asset.get_records() and approved.get_model_attachments()==reference_asset.get_model_attachments(),"exact approved geometry and models "+City.IDS[index])
	for seed_value in [1703,42]:
		var core:RefCounted=ClassDB.instantiate("TerrainCore")
		core.execute(Codec.command(6,[seed_value,25]))
		var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,16)
		var started:=Time.get_ticks_usec()
		var plan:Dictionary=Planner.locate(core,layout.sites[3].position,[],Rect2(),City.recipe,City.streets,Vector2(180,224))
		print("CITY_PLAN seed=",seed_value," result=",plan.get("reason","ok")," ms=",(Time.get_ticks_usec()-started)/1000.0," details=",plan if not plan.get("ok",false) else plan.center)
		check(plan.get("ok",false),"all six roles fit native lots / seed "+str(seed_value))
		if not plan.get("ok",false):continue
		var works:Dictionary=Planner.earthworks(plan)
		var baked:Dictionary=core.bake_generated_earthworks(Works.packets(works.segments))
		check(baked.get("ok",false),"generation-time grading succeeds with no runtime fixup")
		if not baked.get("ok",false):continue
		var vehicle_count:=0
		for lot:Dictionary in plan.lots:
			check(lot.quality.status=="pass" and lot.origin.y+1==int(lot.survey.grade),lot.label+" full envelope respects 2m fill / 3m cut and level entrance")
			var support:PackedVector3Array=lot.asset.foundation_samples(lot.origin,lot.rotation,1)
			var supported:=true
			for offset in range(0,support.size(),512):
				supported=density_matches(core,support.slice(offset,offset+512),baked.revision,true) and supported
			check(supported,lot.label+" every foundation column supported")
			var clear:=true
			for offset in range(0,lot.asset.clearance_sample_count(),512):
				clear=density_matches(core,lot.asset.clearance_samples(lot.origin,lot.rotation,offset,512,1),baked.revision,false,true) and clear
			check(clear,lot.label+" interior envelope clear after all road and foundation edits")
			var surface:=site_point(lot,lot.asset.get_meta("site_entrance"))
			check(density_matches(core,PackedVector3Array([surface+Vector3.UP*.15]),baked.revision,false),lot.label+" doorway is not filled by terrain")
			for driveway:Dictionary in lot.get("vehicle_paths",[]):
				vehicle_count+=1
				check(is_equal_approx(driveway.start.x,driveway.finish.x) and driveway.half_width==2.5,"independent straight five-metre vehicle access / "+lot.label)
		check(vehicle_count==6,"six loading/garage bays receive separate native access routes")
		var copy:Dictionary=plan.duplicate(true)
		for lot:Dictionary in copy.lots:lot.erase("asset")
		FileAccess.open(output.path_join("plan_%d.bin"%seed_value),FileAccess.WRITE).store_var(copy)
		FileAccess.open(output.path_join("terrain_%d.bin"%seed_value),FileAccess.WRITE).store_buffer(core.execute(Codec.command(4)).slice(12))
	if "--full-plan" in OS.get_cmdline_user_args():
		var options:Dictionary=preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS.duplicate()
		options.settlements=3;options.districts=3;options.network=2;options.trails=2
		var full:Dictionary=preload("res://addons/world_runtime/custom_world_plan.gd").build(1703,25,options,output.path_join("inland_plan"))
		print("FULL_CITY_PLAN ",full.get("reason","ok")," sites=",full.get("sites",[]).size()," buildings=",full.get("building_count",0))
		check(full.get("ok",false) and full.sites.size()==9 and full.building_count==86,"maximum inland seed 1703 fits all requested districts without raising terrain budgets")
	print("APPROVED_CITY_GENERATION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
