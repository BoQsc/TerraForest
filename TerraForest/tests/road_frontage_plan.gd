extends SceneTree
const Plan=preload("res://reviews/roads/frontage_plan.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
func run()->void:
	var result:=Plan.build()
	print("FRONTAGE_PLAN ",result.get("reason","")," attempts=",result.attempts," rejected=",result.rejections)
	if not check_plan(result):quit(1);return
	var core:RefCounted=ClassDB.instantiate("TerrainCore")
	core.execute(Plan.Codec.command(6,[1703,21]))
	var center:Vector3=result.trial.center
	var baseline:=Plan.Planner.streets(core,center,Plan.lines(center,false))
	var invalid:=Plan.lines(center,true);invalid[0].frontage_trial=false
	check(not Plan.Planner.streets(core,center,invalid).ok,"mixed enabled/disabled network is rejected atomically")
	invalid=Plan.lines(center,true);invalid[0].frontage_trial="yes"
	check(not Plan.Planner.streets(core,center,invalid).ok,"malformed experimental flag rejected")
	check(Plan.Planner.streets(core,center,Plan.lines(center,false))==baseline,"normal native planning remains deterministic and unchanged by the trial")
	check(Plan.fit(core,center,true).roads==result.trial.roads,"frontage planning is deterministic")
	var continuous:=true
	var previous:Dictionary={}
	for road:Dictionary in result.trial.roads:
		var coefficients:PackedFloat64Array=road.coefficients
		var offset:int=road.curve_index*4
		var endpoint:float=coefficients[offset]+coefficients[offset+1]+coefficients[offset+2]+coefficients[offset+3]
		continuous=continuous and absf(road.start.y-coefficients[offset+3])<.0001 and absf(road.finish.y-endpoint)<.0001
		if not previous.is_empty() and road.curve_index>0:
			var previous_offset:int=previous.curve_index*4
			var tangent:float=3*previous.coefficients[previous_offset]+2*previous.coefficients[previous_offset+1]+previous.coefficients[previous_offset+2]
			continuous=continuous and absf(tangent-coefficients[offset+2])<.0001 and previous.finish.distance_to(road.start)<.0001
		previous=road
	check(continuous,"shared native cubics join with matching heights and tangents")
	var plates:PackedInt32Array=result.trial.block_paving.records
	var block_codec:Node=ClassDB.instantiate("NativeBlockWorld")
	var expected_plate:int=block_codec.encode_block(8,0,2)
	block_codec.free()
	var trusted_plates:=true
	for offset in range(3,plates.size(),4):trusted_plates=trusted_plates and plates[offset]==expected_plate
	check(trusted_plates,"paving uses only the trusted upright concrete quarter-plate block")
	var constrained:=Plan.Market.recipe(center)
	constrained[0].frontage_x=Vector2(NAN,center.x+24)
	check(not Plan.Planner.plan(core,center,result.trial.roads,0,constrained).ok,"non-finite frontage constraints rejected before lot publication")
	var packets:=Plan.Earthworks.packets(result.trial.works.segments)
	var bake:Dictionary=core.bake_generated_earthworks(packets)
	check(bake.get("ok",false),"complete approved-building / road / plate master plan bakes natively")
	var snapshot:PackedByteArray=core.execute(Plan.Codec.command(4)).slice(12)
	var restored:RefCounted=ClassDB.instantiate("TerrainCore")
	var command:=Plan.Codec.command(5);command.append_array(snapshot)
	check(Plan.Codec.reply_ok(restored.execute(command)) and restored.execute(Plan.Codec.command(4)).slice(12)==snapshot,"generated terrain uses the existing binary snapshot format")
	var folder:="res://reports/road_frontage_review"
	DirAccess.make_dir_recursive_absolute(folder)
	var serial:Dictionary=result.duplicate(true)
	for variant in ["baseline","trial"]:
		for lot:Dictionary in serial[variant].lots:lot.erase("asset")
	FileAccess.open(folder.path_join("plan.bin"),FileAccess.WRITE).store_var(serial)
	FileAccess.open(folder.path_join("plan.json"),FileAccess.WRITE).store_string(JSON.stringify(serial,"  "))
	print("ROAD_FRONTAGE_PLAN failures=",failures)
	quit(1 if failures else 0)
func check_plan(result:Dictionary)->bool:
	check(result.get("ok",false),"paired native road plans fit natural terrain at the same location")
	if not result.get("ok",false):return false
	check(result.baseline.lots.size()==4 and result.trial.lots.size()==4,"both street previews use the same four unchanged approved building assets")
	check(result.trial.road_survey.frontages.size()==2 and result.trial.road_survey.frontages.all(func(landing:Dictionary)->bool:return landing.length>=48),"two long near-level building streets with room for gradual end transitions")
	check(result.trial.road_survey.max_grade<=.060001 and result.trial.road_survey.max_cut<=3 and result.trial.road_survey.max_fill<=2,"whole-corridor native survey retains cut/fill and grade limits")
	check(result.trial.block_paving.tiles>0,"trusted individual sidewalk plates retained")
	return true
