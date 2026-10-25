extends SceneTree
const Trial=preload("res://addons/world_runtime/road_grid_trial.gd")
const Earthworks=preload("res://addons/world_runtime/generation_earthworks.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var evidence:=ProjectSettings.globalize_path("res://reports/road_grid_trial")
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	DirAccess.make_dir_recursive_absolute(evidence)
	var native:RefCounted=ClassDB.instantiate("NativeRoadProfile")
	check(not Trial.segments([{}]).ok and not Trial.segments([1]).ok,"incomplete trial descriptors fail without partial output")
	for invalid in [PackedFloat64Array(),PackedFloat64Array([0,0,NAN,35]),PackedFloat64Array([0,0,1,35,0,0,1,38])]:
		check(not native.grid_trial(invalid,22).ok,"invalid/disconnected trial curve rejected")
	for spacing:float in [1.6,22,64]:
		var original:=PackedFloat64Array([-2,3,0,35])
		var fitted:Dictionary=native.grid_trial(original,spacing)
		check(fitted.ok and fitted.coefficients.size()<=256 and spacing/fitted.subdivisions>=1,"bounded native profile / valid stamp spacing")
		var count:int=fitted.coefficients.size()/4
		var end:float=0
		for component in 4:end+=fitted.coefficients[(count-1)*4+component]
		check(absf(fitted.coefficients[3]-35)<0.00001 and absf(end-36)<0.00001,"junction heights remain exactly anchored")
		check(fitted.max_shift<=.30001 and (fitted.max_grade<=.16001 or fitted.weight==0),"certified grading and slope limits or unchanged steep road")
		check(fitted==native.grid_trial(original,spacing),"trial is deterministic")
	var plan:Dictionary=preload("res://addons/world_runtime/custom_world_plan.gd").build(1703,21,{"biome":0,"districts":1,"network":0,"settlements":2,"trails":1},evidence.path_join("plan_cache"))
	check(plan.get("ok",false),"seed 1703 production plan remains available")
	if not plan.get("ok",false):print(plan);quit(1);return
	var baseline:Array=Earthworks.packets(plan.works.segments)
	var trial:Dictionary=Trial.segments(plan.works.segments)
	check(trial.get("ok",false),"entire planned road network accepts optional trial")
	if not trial.get("ok",false):print(trial);quit(1);return
	check(Earthworks.packets(plan.works.segments)==baseline,"trial cannot mutate default plans/packets")
	var selected:Array=[]
	for road:Dictionary in plan.market.roads:
		if road.start.distance_to(road.finish)>10 and absf(road.start.y-road.finish.y)>.5:selected.append(road)
	selected.sort_custom(func(first:Dictionary,second:Dictionary)->bool:return first.start.distance_squared_to(Vector3(989,35,1093))<second.start.distance_squared_to(Vector3(989,35,1093)))
	check(not selected.is_empty(),"sloped settlement road selected for collision comparison")
	if selected.is_empty():quit(1);return
	var road:Dictionary=selected[0]
	var local:Dictionary=Trial.segments([road])
	var core:RefCounted=ClassDB.instantiate("TerrainCore")
	core.execute(Codec.command(6,[1703,21]))
	check(core.bake_generated_earthworks(Earthworks.packets(local.segments)).get("ok",false),"native trial stamps use ordinary editable terrain")
	var snapshot:PackedByteArray=core.execute(Codec.command(4)).slice(12)
	var restored:RefCounted=ClassDB.instantiate("TerrainCore")
	var packet:=Codec.command(5);packet.append_array(snapshot)
	check(Codec.reply_ok(restored.execute(packet)) and restored.execute(Codec.command(4)).slice(12)==snapshot,"trial density edits round-trip without a new save format")
	var diagnostic:={"source_count":baseline.size(),"trial_count":trial.segments.size(),"changed":trial.changed,"max_shift":trial.max_shift,"max_grade":trial.max_grade,"selected":road,"local":local}
	FileAccess.open(evidence.path_join("profile.json"),FileAccess.WRITE).store_string(JSON.stringify(diagnostic,"  "))
	FileAccess.open(evidence.path_join("selected.bin"),FileAccess.WRITE).store_var({"road":road,"trial":local,"market":plan.market,"works":plan.works})
	print("ROAD_GRID_TRIAL failures=",failures," ",diagnostic.source_count," -> ",diagnostic.trial_count," changed=",trial.changed," shift=",trial.max_shift)
	quit(1 if failures else 0)
