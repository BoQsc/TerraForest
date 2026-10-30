# SPDX-License-Identifier: 0BSD
extends "res://tests/approved_large_house.gd"

const City=preload("res://addons/structures/civic_catalog.gd")

func run()->void:
	output="res://reports/civic_generation"
	DirAccess.make_dir_recursive_absolute(output)
	for seed_value in ([1703] if "--full-plan" in OS.get_cmdline_user_args() else [1703,42]):
		var core:RefCounted=ClassDB.instantiate("TerrainCore")
		core.execute(Codec.command(6,[seed_value,29 if "--full-plan" in OS.get_cmdline_user_args() else 25]))
		var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,16)
		var started:=Time.get_ticks_usec()
		var plan:Dictionary=Planner.locate(core,layout.sites[3].position,[],Rect2(),City.recipe,City.streets,Vector2(180,224))
		var full:Dictionary={}
		if "--full-plan" in OS.get_cmdline_user_args():
			full=preload("res://addons/world_runtime/world_generation_plan.gd").build(seed_value,29,true,true,"user://civic_review_plans",preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS,null,true)
			plan=full.plan if full.get("ok",false) else full
		print("CITY_PLAN seed=",seed_value," result=",plan.get("reason","ok")," ms=",(Time.get_ticks_usec()-started)/1000.0," details=",plan if not plan.get("ok",false) else plan.center)
		check(plan.get("ok",false),"all five roles fit native lots / seed "+str(seed_value))
		if not plan.get("ok",false):continue
		var works:Dictionary=full.works if not full.is_empty() else Planner.earthworks(plan)
		var baked:Dictionary=core.bake_generated_earthworks(Works.packets(works.segments))
		check(baked.get("ok",false),"generation-time grading succeeds with no runtime fixup")
		if not baked.get("ok",false):continue
		var vehicle_count:=0
		for lot:Dictionary in plan.lots:
			print("CIVIC_SITE ",lot.label," origin=",lot.origin," bounds=",lot.bounds," pedestrian=",lot.entrance.segment," vehicles=",lot.get("vehicle_paths",[]))
			check(lot.quality.status=="pass" and lot.origin.y+int(lot.asset.get_meta("site_surface_offset"))==int(lot.survey.grade),lot.label+" full envelope respects 2m fill / 3m cut and level entrance")
			var support:PackedVector3Array=lot.asset.foundation_samples(lot.origin,lot.rotation,int(lot.asset.get_meta("site_sample_band")))
			var supported:=true
			for offset in range(0,support.size(),512):
				supported=density_matches(core,support.slice(offset,offset+512),baked.revision,true) and supported
			check(supported,lot.label+" every foundation column supported")
			var clear:=true
			for offset in range(0,lot.asset.clearance_sample_count(),512):
				clear=density_matches(core,lot.asset.clearance_samples(lot.origin,lot.rotation,offset,512,int(lot.asset.get_meta("site_sample_band"))),baked.revision,false,true) and clear
			check(clear,lot.label+" interior envelope clear after all road and foundation edits")
			var surface_count:int=lot.asset.terrain_surface_sample_count(int(lot.asset.get_meta("site_sample_band")))
			var pavement_clear:=surface_count>0
			for at in range(0,surface_count,512):
				pavement_clear=density_matches(core,lot.asset.terrain_surface_samples(lot.origin,lot.rotation,at,512,int(lot.asset.get_meta("site_sample_band"))),baked.revision,false,true) and pavement_clear
			check(pavement_clear,lot.label+" shared native surface gate: floors, aprons, basement slabs and steps")
			var surface:=site_point(lot,lot.asset.get_meta("site_entrance"))
			check(density_matches(core,PackedVector3Array([surface+Vector3.UP*.15]),baked.revision,false),lot.label+" doorway is not filled by terrain")
			for driveway:Dictionary in lot.get("vehicle_paths",[]):
				vehicle_count+=1
				check(is_equal_approx(driveway.start.x,driveway.finish.x) and driveway.half_width==2.5,"independent straight five-metre vehicle access / "+lot.label)
		check(vehicle_count==2,"two warehouse bays receive separate native access routes")
		var copy:Dictionary=plan.duplicate(true)
		for lot:Dictionary in copy.lots:lot.erase("asset")
		FileAccess.open(output.path_join("plan_%d.bin"%seed_value),FileAccess.WRITE).store_var(copy)
		FileAccess.open(output.path_join("terrain_%d.bin"%seed_value),FileAccess.WRITE).store_buffer(core.execute(Codec.command(4)).slice(12))
	print("CIVIC_GENERATION checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func density_matches(core: RefCounted, points: PackedVector3Array, revision: int, solid: bool, allow_contact: bool = false) -> bool:
	var packet := Codec.command(29 if solid else 31, [revision, points.size()])
	packet.append_array(points.to_byte_array())
	var reply: PackedByteArray = core.execute(packet)
	if not Codec.reply_ok(reply) or reply.size() != 20 + points.size() * 4:
		return false
	var mismatches := 0
	for index in points.size():
		var density: float = reply.decode_float(20 + index * 4)
		if density >= 0 if solid else density < 0 if allow_contact else density <= 0:
			if mismatches < 3:
				print("DENSITY_MISMATCH ", points[index], " value=", density, " solid=", solid)
			mismatches += 1
	return mismatches == 0

