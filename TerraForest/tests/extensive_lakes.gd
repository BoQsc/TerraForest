# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Digest=preload("res://addons/world_runtime/survey_cache.gd")
var folder:=""
var failures:=0
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="):folder=arg.trim_prefix("--check-evidence-dir=")
	run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func legacy()->Dictionary:
	var result:Dictionary={}
	var points:=PackedVector3Array()
	for x in range(44,2000,137):
		for z in range(61,2000,151):points.append(Vector3(x+.37,31.25,z+.61))
	for seed_value in [42,1703]:
		for generator in range(1,32):
			var core=ClassDB.instantiate("TerrainCore")
			core.execute(Codec.command(6,[seed_value,generator]))
			var bytes:=PackedByteArray()
			for cmd in [25,27]:bytes.append_array(core.execute(Codec.command(cmd)))
			var request:=Codec.command(37,[points.size()]);request.append_array(points.to_byte_array())
			bytes.append_array(core.execute(request))
			result["%d/%d"%[seed_value,generator]]=Digest.digest(bytes).hex_encode()
	return result
func run()->void:
	var values:=legacy()
	if "--record-legacy" in OS.get_cmdline_user_args():
		FileAccess.open(folder.path_join("legacy.json"),FileAccess.WRITE).store_string(JSON.stringify(values,"  "))
	else:
		check(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/extensive_lakes_legacy.json"))==values,"all 62 frozen legacy field and catalog fingerprints are unchanged")
		for arg:String in OS.get_cmdline_user_args():
			if arg.begins_with("--legacy="):
				check(JSON.parse_string(FileAccess.get_file_as_string(arg.trim_prefix("--legacy=")))==values,"all 62 legacy terrain/lake fingerprints are unchanged")
		var launch=preload("res://demo/world_launch.gd")
		check([launch.terrain_generator(false,true),launch.terrain_generator(true,true),launch.terrain_generator(false,false),launch.terrain_generator(true,false)]==[32,33,34,35],"normal creation keeps independent ocean and buildable-ground choices")
		var recipe=preload("res://addons/world_runtime/world_recipe.gd").codec()
		var paving_a:=PackedInt32Array([10,40,10,192,11,40,10,192]);var paving_b:=PackedInt32Array([11,40,10,192,12,40,10,192])
		var shared:Dictionary=recipe.coalesce_paving([paving_a,paving_b])
		check(shared.get("ok",false) and shared.shared_cells==1 and shared.unique_cells==3 and shared.regions[0]==paving_a and shared.regions[1]==PackedInt32Array([12,40,10,192]),"adjacent districts retain one owner for identical shared sidewalk cells")
		check(not recipe.coalesce_paving([paving_a,PackedInt32Array([11,40,10,193])]).get("ok",false),"conflicting paving materials reject instead of overwriting")
		check(not recipe.coalesce_paving([PackedInt32Array([1,2,3])]).get("ok",false) and not recipe.coalesce_paving([PackedInt32Array([-1,40,10,192])]).get("ok",false),"malformed and out-of-world paving rejects")
		var rows:Array=[]
		for seed_value in [0,42,1703,9137]:
			for generator in [32,33,34,35]:
				var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,generator]))
				var definitions:Dictionary=preload("res://addons/volumetric_terrain/generated_lakes.gd").describe(core,generator)
				check(definitions.get("ok",false) and definitions.records.size()<=16,"bounded catalog %d/%d"%[seed_value,generator])
				var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode(definitions.records)
				check(not catalog.is_empty(),"unchanged native catalog accepts every section")
				var audit:Dictionary=core.survey_generated_lake_surfaces(definitions.records)
				check(audit.get("ok",false) and int(audit.get("extensive_count",0))>=3,"three connected lakes exceed 330 m: %d/%d"%[seed_value,generator])
				var shores_closed:=true
				for lake:Dictionary in audit.get("lakes",[]):
					var bounds:=AABB(lake.center,Vector3.ZERO)
					for section:Dictionary in definitions.records:
						if absf(section.level-lake.center.y)<.001:bounds=bounds.merge(AABB(section.origin,Vector3(section.cells)*section.spacing))
					for p:Vector3 in audit.points:
						if absf(p.y-lake.center.y)>.001:continue
						if p.x<=bounds.position.x+2 or p.z<=bounds.position.z+2 or p.x>=bounds.end.x-2 or p.z>=bounds.end.z-2:shores_closed=false
				check(shores_closed,"physical shores close before catalog limits; internal section seams remain open")
				audit.erase("points");audit["seed"]=seed_value;audit["generator"]=generator;rows.append(audit)
				if generator==33 and seed_value in [42,1703] and "--skip-bake" not in OS.get_cmdline_user_args():
					var revision:int=core.execute(Codec.command(0)).decode_u32(12);var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
					var baked:Dictionary=ClassDB.instantiate("NativeGeneratedLakeBake").run(core,catalog,revision,epoch,60000)
					check(baked.get("ok",false),"long lakes fill within existing native time and memory caps")
					if not baked.get("ok",false):print("BAKE_FAILED ",baked);continue
					var water=ClassDB.instantiate("NativeRegionalWater")
					check(water.restore_snapshot(baked.snapshot),"fresh native water restores complete long lakes")
					var snapshot:PackedByteArray=water.capture_streaming_snapshot(catalog)
					# Restore can mark rounded boundary cells for ordinary settlement. Only
					# that pending bit may change; every quantity/contact byte must survive.
					var expected:PackedByteArray=baked.snapshot.duplicate();var marked:=0
					if snapshot.size()==expected.size():
						for region in expected.decode_u32(12):
							var flags:=32+expected.decode_u32(8)+region*9076+12
							if snapshot.decode_u32(flags)&16 and not expected.decode_u32(flags)&16:marked+=1
							expected.encode_u32(flags,expected.decode_u32(flags)|(snapshot.decode_u32(flags)&16))
					check(snapshot==expected,"restore preserves every quantity/contact byte and only adds pending-settlement flags")
					var reopened=ClassDB.instantiate("NativeRegionalWater")
					check(reopened.restore_snapshot(snapshot) and reopened.capture_streaming_snapshot(catalog)==snapshot,"canonical saved water reopens byte-for-byte")
					baked["rounding_settlement_regions"]=marked;baked["snapshot_sha256"]=Digest.digest(snapshot).hex_encode()
					var seams:=0;var wet_seams:=0
					for i in definitions.records.size():
						var a:Dictionary=definitions.records[i];var ab:=AABB(a.origin,Vector3(a.cells)*a.spacing)
						for j in range(i+1,definitions.records.size()):
							var b:Dictionary=definitions.records[j];var bb:=AABB(b.origin,Vector3(b.cells)*b.spacing)
							if absf(a.level-b.level)>.001:continue
							var p:=Vector3.ZERO;var axis:=Vector3.ZERO
							if ab.end.x==bb.position.x and ab.position.z==bb.position.z:p=Vector3(ab.end.x,a.level-.5,lerpf(a.seed.z,b.seed.z,.5));axis=Vector3.RIGHT
							elif ab.end.z==bb.position.z and ab.position.x==bb.position.x:p=Vector3(lerpf(a.seed.x,b.seed.x,.5),a.level-.5,ab.end.z);axis=Vector3.BACK
							else:continue
							seams+=1
							if water.depth_at(p-axis*.75)>.1 and water.depth_at(p+axis*.75)>.1:wet_seams+=1
					check(seams==6 and wet_seams==seams,"real restored water crosses all six section seams")
					baked.erase("snapshot");audit["bake"]=baked
		FileAccess.open(folder.path_join("lakes.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"profiles":rows},"  "))
	print("EXTENSIVE_LAKES failures=",failures)
	quit(1 if failures else 0)
