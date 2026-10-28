extends "res://tests/distributed_generation.gd"

const OUTPUT:="res://reports/lake_landscape"

func run()->void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var legacy:={}
	for seed_value in [0,42,1703]:
		for generator in [24,25,26,27]:
			var core:RefCounted=ClassDB.instantiate("TerrainCore")
			core.execute(Codec.command(6,[seed_value,generator]))
			legacy["%d/%d"%[seed_value,generator]]=field_signature(core)
	if "--baseline" in OS.get_cmdline_user_args():
		FileAccess.open(OUTPUT+"/legacy.json",FileAccess.WRITE).store_string(JSON.stringify(legacy,"  "))
		print("LAKE_LEGACY_CAPTURE failures=0");quit();return
	check(legacy==JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/lake_landscape_legacy.json")),"previous twelve distributed landscapes and catalogs are unchanged")
	var reports:=[]
	for seed_value in [0,42,1703]:
		for generator in [28,29,30,31]:
			var core:RefCounted=ClassDB.instantiate("TerrainCore")
			check(Codec.reply_ok(core.execute(Codec.command(6,[seed_value,generator]))),"new native profile initializes")
			var definitions:Dictionary=Lakes.describe(core,generator)
			check(definitions.get("ok",false) and definitions.records.size()>=10,"varied lakes retain world coverage / %d / %d"%[seed_value,generator])
			var largest:=0.0;var surfaces:=0;var shapes:={};var closed:=true
			for lake:Dictionary in definitions.get("records",[]):
				var survey:Dictionary=core.survey_generated_lake_surfaces([lake])
				check(survey.get("ok",false) and survey.points.size()>12,"catalog has connected, surveyable water")
				if not survey.get("ok",false):continue
				var low:=Vector3.INF;var high:=-Vector3.INF
				for point:Vector3 in survey.points:low=low.min(point);high=high.max(point)
				largest=maxf(largest,maxf(high.x-low.x,high.z-low.z));surfaces+=survey.points.size()
				shapes[Vector2i(lake.cells.x,lake.cells.z)*int(lake.spacing)]=true
				var end:Vector3=lake.origin+Vector3(lake.cells)*lake.spacing
				closed=closed and low.x>lake.origin.x+2 and low.z>lake.origin.z+2 and high.x<end.x-2 and high.z<end.z-2
			check(closed,"connected lake surfaces stay inside storage bounds without clipped water edges")
			check(largest>160 and shapes.size()>=6,"larger water and varied dimensions exist")
			if generator==29 and "--storage" in OS.get_cmdline_user_args():
				var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode(definitions.records)
				var baked:Dictionary=ClassDB.instantiate("NativeGeneratedLakeBake").run(core,catalog,0,core.execute(Codec.command(13)).decode_u32(12))
				check(baked.get("ok",false),"larger lakes fit unchanged bake and snapshot budgets")
				if baked.get("ok",false):
					var water:RefCounted=ClassDB.instantiate("NativeRegionalWater")
					check(water.restore_snapshot(baked.snapshot),"larger lake snapshot restores")
					var saved:Variant=water.capture_storage_snapshot(catalog)
					check((saved.serialize_snapshot() if saved is RefCounted else saved)==baked.snapshot,"water volume and contacts roundtrip exactly")
				baked.erase("snapshot");reports.append({"seed":seed_value,"storage":baked})
			var crossings:Dictionary=core.plan_lake_crossings()
			print("LAKE_CROSSINGS seed=",seed_value," generator=",generator," count=",crossings.get("crossings",[]).size())
			reports.append({"seed":seed_value,"generator":generator,"lakes":definitions.records.size(),"largest_m":largest,"surface_samples":surfaces,"crossings":crossings})
	FileAccess.open(OUTPUT+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"reports":reports},"  "))
	print("LAKE_LANDSCAPE checks=",checks," failures=",failures);quit(1 if failures else 0)
