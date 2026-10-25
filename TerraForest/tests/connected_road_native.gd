extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->void:
	print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
func road(start:Vector3,finish:Vector3)->Dictionary:
	return {"start":start,"finish":finish,"half_width":4.0,"depth":3.0,"clearance":4.0,"shoulder":0.0,"material":4,"bounds":AABB(start,Vector3.ZERO).expand(finish).grow(8)}
func height(record:Dictionary,fraction:float)->float:
	if not record.has("coefficients"):return lerpf(record.start.y,record.finish.y,fraction)
	var curve:PackedFloat64Array=record.coefficients;var offset:int=record.curve_index*4
	return ((curve[offset]*fraction+curve[offset+1])*fraction+curve[offset+2])*fraction+curve[offset+3]
func slope(record:Dictionary,fraction:float)->float:
	var distance:=Vector2(record.finish.x-record.start.x,record.finish.z-record.start.z).length()
	if not record.has("coefficients"):return (record.finish.y-record.start.y)/distance
	var curve:PackedFloat64Array=record.coefficients;var offset:int=record.curve_index*4
	return ((3*curve[offset]*fraction+2*curve[offset+1])*fraction+curve[offset+2])/distance
func run()->void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,23]))
	var source:=road(Vector3(1088,49.1879,800),Vector3(1056,44.6812,896))
	var result:Dictionary=core.fit_road_network([source],[])
	check(result.get("ok",false),"reported corridor receives a valid connected grade")
	if result.get("ok",false):
		check(result.changed>0 and result.contact_after>result.contact_before,"road geometry changes and integer footprint contact improves")
		check(result.max_shift<=.555 and result.max_grade<=.201 and result.max_curvature<=.04001 and result.max_cut<=3.001 and result.max_fill<=2.001,"bounded displacement, exact cubic grade/curvature and full-width earthworks")
		check(result==core.fit_road_network([source],[]),"native solution deterministic")
		var continuous:=true
		for index in range(1,result.segments.size()):
			var before:Dictionary=result.segments[index-1];var after:Dictionary=result.segments[index]
			continuous=continuous and before.finish.distance_to(after.start)<.00001 and absf(height(before,1)-height(after,0))<.00001 and absf(slope(before,1)-slope(after,0))<.00001
		check(continuous,"all generated joins share position, height and tangent")
	var midpoint:Vector3=(source.start+source.finish)*.5
	var joined:Dictionary=core.fit_road_network([road(source.start,midpoint),road(midpoint,source.finish)],[])
	check(joined.get("ok",false),"connected source segments fit together")
	if joined.get("ok",false):
		var ends:Array=[]
		for segment:Dictionary in joined.segments:
			for point:Vector3 in [segment.start,segment.finish]:
				if Vector2(point.x,point.z).distance_to(Vector2(midpoint.x,midpoint.z))<.001:ends.append(point.y)
		check(ends.size()==2 and absf(ends[0]-ends[1])<.00001,"shared source junction has one height")
	var reserved:Dictionary=core.fit_road_network([source],[Rect2(1040,790,64,120)])
	check(reserved.get("ok",false) and reserved.get("segments",[])==[source],"protected road and entrances remain unchanged")
	var level:=road(Vector3(1080,48,820),Vector3(1080,48,844))
	var flat:Dictionary=core.fit_road_network([level],[])
	check(flat.get("ok",false) and flat.get("segments",[])==[level],"integer flat road remains unchanged")
	for field:String in ["start","finish","half_width","depth","clearance","shoulder","material","bounds"]:
		var invalid:=source.duplicate();invalid.erase(field)
		check(not core.fit_road_network([invalid],[]).get("ok",false),"missing descriptor rejected: "+field)
	for invalid_value in [NAN,INF,-1.0,1000000.0]:
		var invalid:=source.duplicate();invalid.shoulder=invalid_value
		check(not core.fit_road_network([invalid],[]).get("ok",false),"invalid shoulder fails explicitly")
	var outside:=source.duplicate();outside.start=Vector3(1e20,48,800)
	check(not core.fit_road_network([outside],[]).get("ok",false),"out-of-world endpoints rejected before graph indexing")
	var invalid_bounds:=source.duplicate();invalid_bounds.bounds="not bounds"
	check(not core.fit_road_network([invalid_bounds],[]).get("ok",false),"invalid bounds type rejected")
	check(not core.fit_road_network([source],[Rect2(Vector2(NAN,0),Vector2.ONE)]).get("ok",false),"nonfinite protected bounds rejected")
	check(not core.fit_road_network([],[]).get("ok",false),"empty request rejected")
	var policy_source:=source.duplicate();policy_source["support_half_width"]=6.5;policy_source["support_shoulder"]=0.0
	var policy:Dictionary=core.fit_road_network([policy_source],[],true)
	check(policy.get("ok",false) and policy.get("footprints",0)>0 and policy.get("contact_cost_after",INF)<policy.get("contact_cost_before",0),"generation-native footprint policy improves contact before baking")
	check(policy==core.fit_road_network([policy_source],[],true),"footprint policy is deterministic")
	check(not policy.get("quality_complete",true),"remaining bad footprints cannot be reported as complete")
	var policy_protected:Dictionary=core.fit_road_network([policy_source],[Rect2(Vector2(1040,780),Vector2(80,140))],true)
	check(policy_protected.get("ok",false) and policy_protected.get("segments",[])==[policy_source],"footprint policy preserves protected grades exactly")
	var invalid_support:=policy_source.duplicate();invalid_support.support_half_width=NAN
	check(not core.fit_road_network([invalid_support],[],true).get("ok",false),"invalid generated support envelope rejected")
	invalid_support.support_half_width=3.0
	check(not core.fit_road_network([invalid_support],[],true).get("ok",false),"support envelope cannot omit paved surface")
	var collision_report:Dictionary={}
	if result.get("ok",false):collision_report=await inspect_collision(core,result.segments)
	var policy_collision:Dictionary={}
	if policy.get("ok",false):
		core.execute(Codec.command(6,[1703,23]));policy_collision=await inspect_collision(core,policy.segments)
	DirAccess.make_dir_recursive_absolute("res://reports")
	var report:=result.duplicate();report.erase("segments");report["failures"]=failures;report["variant"]=core.build_variant()
	report["collision"]=collision_report
	report["footprint_collision"]=policy_collision
	FileAccess.open("res://reports/connected_road_native.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("CONNECTED_ROAD_NATIVE failures=",failures);quit(1 if failures else 0)
func inspect_collision(core:RefCounted,segments:Array)->Dictionary:
	var authored:=true
	for segment:Dictionary in segments:
		authored=Codec.reply_ok(core.execute(Codec.curved_road_bed(segment.start,segment.finish,6.5,3,4,segment.coefficients,segment.curve_index))) and authored
	check(authored,"all connected curve sections bake into editable terrain")
	var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
	var faces:=PackedVector3Array()
	for across in range(1040,1104,16):
		for along in range(784,912,16):
			var mesh:Dictionary=Codec.decode_mesh(core.build_owned_region(across,along,16,1,32,64,epoch))
			if mesh.has("error"):check(false,"native road mesh builds");return {}
			faces.append_array(mesh.faces)
	var body:=StaticBody3D.new();body.collision_layer=1
	var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces)
	var collision:=CollisionShape3D.new();collision.shape=shape;body.add_child(collision);root.add_child(body)
	await physics_frame;await physics_frame
	var start:Vector3=segments[0].start;var finish:Vector3=segments[-1].finish
	var axis:=Vector2(finish.x-start.x,finish.z-start.z);var side:=Vector2(-axis.y,axis.x).normalized()
	var samples:=0;var missing:=0;var error:=0.0;var step_error:=0.0
	for lateral:float in [-3,0,3]:
		var previous_actual:=NAN;var previous_expected:=NAN
		for station in range(1,floori(axis.length()*4)):
			var fraction:=station*.25/axis.length();var part:=fraction*segments.size();var index:=mini(segments.size()-1,floori(part))
			var expected:=height(segments[index],part-index)
			var point:=Vector2(start.x,start.z)+axis*fraction+side*lateral
			var ray:=PhysicsRayQueryParameters3D.create(Vector3(point.x,expected+1,point.y),Vector3(point.x,expected-1,point.y),1)
			var hit:=root.get_world_3d().direct_space_state.intersect_ray(ray);samples+=1
			if hit.is_empty():missing+=1;continue
			var actual:float=hit.position.y;error=maxf(error,absf(actual-expected))
			if is_finite(previous_actual):step_error=maxf(step_error,absf(actual-previous_actual-expected+previous_expected))
			previous_actual=actual;previous_expected=expected
	body.free()
	check(missing==0 and error<=.03 and step_error<=.02,"baked collision follows connected grade without join steps across three lanes")
	return {"samples":samples,"missing":missing,"max_height_error":error,"max_step_error":step_error,"spacing":.25}
