extends SceneTree
const Trial=preload("res://addons/world_runtime/road_grid_trial.gd")
const Earthworks=preload("res://addons/world_runtime/generation_earthworks.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var evidence:="res://reports/road_burial_trial"
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func evaluate(coefficients:PackedFloat64Array,section:int,position:float)->float:
	var offset:=section*4
	return ((coefficients[offset]*position+coefficients[offset+1])*position+coefficients[offset+2])*position+coefficients[offset+3]
func run()->void:
	DirAccess.make_dir_recursive_absolute(evidence)
	var native:RefCounted=ClassDB.instantiate("NativeRoadProfile")
	for invalid in [PackedFloat64Array(),PackedFloat64Array([0,0,NAN,35]),PackedFloat64Array([0,0,1,35,0,0,1,38])]:
		check(not native.burial_trial(invalid,22).ok,"invalid or disconnected road rejected")
	var records:Array=[]
	for spacing:float in [1.6,15,32,64,100]:
		for rise:float in [-2,-1,0,1,2]:
			var original:=PackedFloat64Array([-2*rise,3*rise,0,35.08])
			var fitted:Dictionary=native.burial_trial(original,spacing)
			check(fitted.ok and fitted.coefficients.size()<=256 and spacing/fitted.subdivisions>=1,"bounded native profile")
			check(fitted==native.burial_trial(original,spacing),"deterministic profile")
			check(fitted.max_shift<=.180001 and fitted.max_raise<=.000001 and fitted.max_grade_change<=.025001 and fitted.max_curvature_change<=.010001,"continuous cubic cut, slope-change and curvature certificates")
			check(fitted.max_grade<=.160001 or fitted.weight==0,"steep roads unchanged rather than forced into a new shape")
			var count:int=fitted.coefficients.size()/4
			check(absf(evaluate(fitted.coefficients,0,0)-35.08)<.00001 and absf(evaluate(fitted.coefficients,count-1,1)-(35.08+rise))<.00001,"junction endpoints anchored")
			check(absf(fitted.coefficients[2])<.00001 and absf(3*fitted.coefficients[(count-1)*4]+2*fitted.coefficients[(count-1)*4+1]+fitted.coefficients[(count-1)*4+2])<.00001,"junction tangents anchored")
			var continuous:=true
			for section in range(1,count):
				var offset:=(section-1)*4
				continuous=continuous and absf(evaluate(fitted.coefficients,section-1,1)-evaluate(fitted.coefficients,section,0))<.00001 and absf(3*fitted.coefficients[offset]+2*fitted.coefficients[offset+1]+fitted.coefficients[offset+2]-fitted.coefficients[section*4+2])<.00001
			check(continuous,"continuous height and slope at every generated join")
			if rise==0:check(fitted.coefficients==original,"flat streets unchanged, no local bowls")
			records.append({"spacing":spacing,"rise":rise,"fit":fitted})
	var chain:=PackedFloat64Array([-2,3,0,35,0,0,0,36,2,-3,0,36])
	var joined:Dictionary=native.burial_trial(chain,24)
	var anchored:=true
	for section in 3:
		anchored=anchored and absf(evaluate(joined.coefficients,section*joined.subdivisions,0)-evaluate(chain,section,0))<.00001
		anchored=anchored and absf(joined.coefficients[section*joined.subdivisions*4+2])<.00001
	check(anchored,"internal road junction heights and tangents remain anchored")
	for section in range(joined.subdivisions,joined.subdivisions*2):
		check(absf(evaluate(joined.coefficients,section,.5)-36)<.00001,"flat section inside a mixed road chain stays untouched")
	var plan:Dictionary=preload("res://addons/world_runtime/custom_world_plan.gd").build(1703,21,{"biome":0,"districts":1,"network":0,"settlements":2,"trails":1},evidence.path_join("plan_cache"))
	check(plan.get("ok",false),"unchanged production plan available")
	if not plan.get("ok",false):print(plan);quit(1);return
	var baseline:Array=Earthworks.packets(plan.works.segments)
	var trial:Dictionary=Trial.segments(plan.works.segments,true)
	check(trial.get("ok",false) and trial.changed>0,"optional adapter covers planned roads without altering the plan")
	check(baseline==Earthworks.packets(plan.works.segments),"normal plan and generation packets remain byte-identical")
	var selected:Array=[]
	for road:Dictionary in plan.market.roads:
		if road.start.distance_to(road.finish)>10 and absf(road.start.y-road.finish.y)>.5:selected.append(road)
	selected.sort_custom(func(first:Dictionary,second:Dictionary)->bool:return first.start.distance_squared_to(Vector3(989,35,1093))<second.start.distance_squared_to(Vector3(989,35,1093)))
	if selected.is_empty():check(false,"sloped comparison road available");quit(1);return
	var road:Dictionary=selected[0]
	var local:=Trial.segments([road],true)
	check(local.ok and local.changed==1,"actual troublesome road receives bounded correction")
	var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,21]))
	check(core.bake_generated_earthworks(Earthworks.packets(local.segments)).get("ok",false),"generation-time correction bakes into ordinary editable density")
	var snapshot:PackedByteArray=core.execute(Codec.command(4)).slice(12)
	var restored:RefCounted=ClassDB.instantiate("TerrainCore")
	var packet:=Codec.command(5);packet.append_array(snapshot)
	check(Codec.reply_ok(restored.execute(packet)) and restored.execute(Codec.command(4)).slice(12)==snapshot,"binary terrain snapshot round-trip")
	FileAccess.open(evidence.path_join("selected.bin"),FileAccess.WRITE).store_var({"road":road,"trial":local})
	var certificate:Dictionary=native.burial_trial(road.coefficients,Vector2(road.finish.x-road.start.x,road.finish.z-road.start.z).length())
	FileAccess.open(evidence.path_join("profile.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"source_count":baseline.size(),"trial_count":trial.segments.size(),"changed":trial.changed,"max_shift":trial.max_shift,"selected":road,"local":local,"certificate":certificate,"cases":records},"  "))
	print("ROAD_BURIAL_TRIAL failures=",failures)
	quit(1 if failures else 0)
