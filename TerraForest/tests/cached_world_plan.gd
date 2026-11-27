# SPDX-License-Identifier: 0BSD
extends SceneTree
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
const Custom=preload("res://addons/world_runtime/custom_world_plan.gd")
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
var folder:=""
var reference:=""
var rekey:=false
func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="):folder=argument.trim_prefix("--check-evidence-dir=")
		if argument.begins_with("--plan-reference="):reference=argument.trim_prefix("--plan-reference=")
		if argument=="--verify-native-rekey":rekey=true
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
	var valid:bool=result.get("ok",false) and (result.get("cache_hit",false) or rekey) and independent_ok
	if overlap:valid=valid and resources.independent_completed>0 and resources.independent_pending.is_empty()
	var identity:Dictionary={"plan_digest":result.get("plan_digest",""),"recipe_key":result.get("recipe_key",""),"lots":[]}
	for site:Dictionary in result.get("sites",[]):
		for lot:Dictionary in site.lots:
			identity.lots.append({"kind":site.recipe_kind,"origin":str(lot.origin),"rotation":lot.rotation,"fingerprint":Custom.prefab_fingerprint(lot.asset)})
	if not reference.is_empty():
		var expected=JSON.parse_string(FileAccess.get_file_as_string(reference))
		# JSON parses numeric fields as floats; normalize the observation too.
		var normalized=JSON.parse_string(JSON.stringify(identity))
		if rekey and expected is Dictionary:
			var before:String=expected.identity.recipe_key;var after:String=identity.recipe_key
			# Rebuilding structures must invalidate the plan cache. Require that
			# this is the only key change, and compare the entire cached payload.
			var old_parts:=before.split("|");var new_parts:=after.split("|")
			valid=valid and old_parts.size()==new_parts.size() and old_parts.size()>5
			if old_parts.size()>5 and new_parts.size()>5:
				old_parts[5]=new_parts[5]
				valid=valid and old_parts==new_parts and same_plan_content(before,after)
			expected.identity.erase("recipe_key");expected.identity.erase("plan_digest")
			normalized.erase("recipe_key");normalized.erase("plan_digest")
		valid=valid and expected is Dictionary and expected.identity==normalized
	elif rekey:valid=false
	# The native plan key/checksum and every hydrated prefab are compared above.
	# Reusing recipes must not introduce shared mutable assets across districts.
	var owners:Dictionary={}
	for site_index in (result.get("sites",[]).size() if result.get("cache_hit",false) else 0):
		var kind:String=result.sites[site_index].recipe_kind
		if not owners.has(kind):owners[kind]={}
		for lot:Dictionary in result.sites[site_index].lots:
			var id:int=lot.asset.get_instance_id()
			if owners[kind].has(id) and owners[kind][id]!=site_index:valid=false
			owners[kind][id]=site_index
	var observation:Dictionary={"ok":valid,"identity":identity,"worker_ms":result.get("worker_ms"),"cache_hit":result.get("cache_hit",false),"native_rekey_verified":rekey and valid,"cache_profile":result.get("cache_profile",{}),"frames":frames,"independent_started":resources.independent_started,"independent_completed":resources.independent_completed}
	FileAccess.open(folder.path_join("cached_plan.json"),FileAccess.WRITE).store_string(JSON.stringify(observation,"  "))
	print("CACHED_WORLD_PLAN failures=",0 if valid else 1," worker_ms=",result.get("worker_ms")," profile=",result.get("cache_profile",{})," lots=",identity.lots.size())
	quit(0 if valid else 1)

func same_plan_content(before:String,after:String)->bool:
	var plans:Array=[]
	for key:String in [before,after]:
		var path:="user://generation_plans/recipe_%d_%s.bin"%[Custom.VERSION,Custom.Survey.digest(key.to_utf8_buffer()).hex_encode()]
		var bytes:=FileAccess.get_file_as_bytes(path)
		if bytes.size()<40 or Custom.Survey.digest(bytes.slice(32))!=bytes.slice(0,32):return false
		var plan=bytes_to_var(bytes.slice(32))
		if not plan is Dictionary or plan.get("recipe_key")!=key:return false
		plan.erase("recipe_key")
		# These two factories store observation timings in the cached payload.
		# A native rebuild must preserve their sites/segments, not elapsed time.
		for section:String in ["exploration","watchtowers"]:
			if plan.has(section):plan[section].erase("worker_ms")
		plans.append(plan)
	var same:bool=var_to_bytes(plans[0])==var_to_bytes(plans[1])
	if not same:
		for key in plans[0]:
			if not plans[1].has(key) or var_to_bytes(plans[0][key])!=var_to_bytes(plans[1][key]):print("PLAN_CONTENT_DIFFERENCE ",key)
	return same
