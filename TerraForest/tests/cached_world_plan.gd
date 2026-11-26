# SPDX-License-Identifier: 0BSD
extends SceneTree
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
const Custom=preload("res://addons/world_runtime/custom_world_plan.gd")
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
var folder:=""
var reference:=""
func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="):folder=argument.trim_prefix("--check-evidence-dir=")
		if argument.begins_with("--plan-reference="):reference=argument.trim_prefix("--plan-reference=")
	run.call_deferred()
func run()->void:
	Engine.max_fps=60
	var resources=preload("res://addons/world_runtime/startup_resources.gd").new()
	var overlap:bool="--overlap-resources" in OS.get_cmdline_user_args()
	var independent_ok:bool=resources.begin_independent("res://demo/world.gd") if overlap else true
	var worker:=Thread.new();var frames:=0
	if worker.start(Plan.build.bind(1703,29,true,true,"user://generation_plans",Recipe.DEFAULTS))!=OK:quit(1);return
	while worker.is_alive():
		if overlap and independent_ok:independent_ok=resources.advance_independent()
		await process_frame;frames+=1
	var result:Dictionary=worker.wait_to_finish()
	if overlap:independent_ok=await resources.finish_independent(root) and independent_ok
	var valid:bool=result.get("ok",false) and result.get("cache_hit",false) and independent_ok
	if overlap:valid=valid and resources.independent_completed>0 and resources.independent_pending.is_empty()
	var identity:Dictionary={"plan_digest":result.get("plan_digest",""),"recipe_key":result.get("recipe_key",""),"lots":[]}
	for site:Dictionary in result.get("sites",[]):
		for lot:Dictionary in site.lots:
			identity.lots.append({"kind":site.recipe_kind,"origin":str(lot.origin),"rotation":lot.rotation,"fingerprint":Custom.prefab_fingerprint(lot.asset)})
	if not reference.is_empty():
		var expected=JSON.parse_string(FileAccess.get_file_as_string(reference))
		# JSON parses numeric fields as floats; normalize the observation too.
		valid=valid and expected is Dictionary and expected.identity==JSON.parse_string(JSON.stringify(identity))
	# The native plan key/checksum and every hydrated prefab are compared above.
	# Reusing recipes must not introduce shared mutable assets across districts.
	var owners:Dictionary={}
	for site_index in result.get("sites",[]).size():
		var kind:String=result.sites[site_index].recipe_kind
		if not owners.has(kind):owners[kind]={}
		for lot:Dictionary in result.sites[site_index].lots:
			var id:int=lot.asset.get_instance_id()
			if owners[kind].has(id) and owners[kind][id]!=site_index:valid=false
			owners[kind][id]=site_index
	var observation:Dictionary={"ok":valid,"identity":identity,"worker_ms":result.get("worker_ms"),"cache_profile":result.get("cache_profile",{}),"frames":frames,"independent_started":resources.independent_started,"independent_completed":resources.independent_completed}
	FileAccess.open(folder.path_join("cached_plan.json"),FileAccess.WRITE).store_string(JSON.stringify(observation,"  "))
	print("CACHED_WORLD_PLAN failures=",0 if valid else 1," worker_ms=",result.get("worker_ms")," profile=",result.get("cache_profile",{})," lots=",identity.lots.size())
	quit(0 if valid else 1)
