# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
	var folder:=""
	var source:=""
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--inspector-fixtures="):folder=argument.trim_prefix("--inspector-fixtures=")
		if argument.begins_with("--verify-source="):source=argument.trim_prefix("--verify-source=")
	if folder.is_empty():quit(1);return
	var archive:RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var region:RefCounted=ClassDB.instantiate("NativeGeneratedRegion")
	var recipe:RefCounted=ClassDB.instantiate("NativeWorldRecipe")
	var original:Dictionary={}
	for name:String in ["original.trw","edited.trw"]:
		var bytes:=FileAccess.get_file_as_bytes(folder.path_join(name))
		var decoded:Dictionary=archive.decode(bytes)
		check(decoded.get("ok",false),"native container accepts inspector bytes: "+name)
		if not decoded.get("ok",false):continue
		check(archive.encode(decoded.sections)==bytes,"native encoder reproduces inspector bytes exactly: "+name)
		check(region.restore_snapshot(decoded.sections.generated_region) and recipe.restore_snapshot(decoded.sections.world_recipe_v1),"native metadata validators accept inspector bytes: "+name)
		var plan:Dictionary=region.get_plan()
		check(plan.seed==1703 and plan.generator==33 and plan.places[0].id==3000 and plan.roads.size()==1,"native restore retains seed, generator, IDs and roads")
		check(plan.places[0].title==("Flats" if name=="original.trw" else "Courtyard flats"),"JSON label edit reaches native restore")
		if original.is_empty():original=decoded.sections
		else:
			for section:String in original:
				if section!="generated_region":check(original[section]==decoded.sections[section],"unchanged binary section: "+section)
	var verifier:RefCounted=ClassDB.instantiate("NativeGeneratedWorldVerifier")
	check(not verifier.inspect(folder.path_join("missing.trw")).get("ok",false),"native verifier rejects missing root")
	check(not verifier.inspect(folder.path_join("original.trw")).get("ok",false),"native verifier rejects synthetic root without companions")
	check(not DirAccess.dir_exists_absolute(folder.path_join("original.trw.regions")),"rejection creates no companion directory")
	if not source.is_empty():
		var before:=FileAccess.get_file_as_bytes(source)
		var decoded:Dictionary=archive.decode(before)
		check(decoded.get("ok",false),"comparison source has valid native root")
		if decoded.get("ok",false):
			region.restore_snapshot(decoded.sections.generated_region)
			var plan:Dictionary=region.get_plan()
			var options:Dictionary=recipe.decode(decoded.sections.world_recipe_v1)
			var reference:Dictionary=preload("res://tests/fixtures/generated_world_verifier_reference.gd").verify(source,plan.seed,plan.generator,options)
			var current:Dictionary=verifier.inspect(source)
			check(reference.get("ok",false) and current.get("ok",false),"both verifiers accept generated companion stores")
			var empty_hashes_ok:=true
			for name:String in decoded.sections:
				if decoded.sections[name].is_empty():
					empty_hashes_ok=empty_hashes_ok and current.get("section_digests",{}).get(name,"")=="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
			check(empty_hashes_ok,"empty sections retain the canonical SHA-256 digest")
			print("WORLD_VERIFIER_TIMING reference_ms=",reference.get("milliseconds",-1)," native_ms=",current.get("milliseconds",-1))
			reference.erase("milliseconds");current.erase("milliseconds")
			check(reference==current,"native verifier exactly matches reference fields and hashes")
			check(FileAccess.get_file_as_bytes(source)==before,"verification leaves source root unchanged")
	print("WORLD_INSPECTOR checks=",checks," failures=",failures)
	quit(1 if failures else 0)
