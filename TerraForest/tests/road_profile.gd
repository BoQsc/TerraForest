# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var planner=ClassDB.instantiate("NativeRoadProfile")
	var flat:=PackedVector3Array([Vector3(100,50,100),Vector3(116,50,100),Vector3(132,50,100)])
	var result: Dictionary=planner.fit(flat,0.25,0.008,15,3)
	check(result.ok and result.max_grade==0 and result.max_curvature==0,"flat route preserved")
	var samples:=PackedVector3Array()
	for y in [47,50.86719,52.5065,54.38694,54.49004,54.00453,54.51068,55.72586,58.96295,64.58889,71.58327,77.87991,84.17345,90.59405,96.38563,102.0208,107.1831,109.9728,111.9581,115.8535,119.5132]:
		samples.append(Vector3(800-samples.size()*16,y,1310))
	var before:=samples.duplicate();var begin:=Time.get_ticks_usec()
	result=planner.fit(samples,0.25,0.008,15,3)
	var elapsed:=Time.get_ticks_usec()-begin
	check(result.ok,"actual uphill terrain admits bounded smooth profile")
	check(samples==before,"planning does not mutate input terrain samples")
	if result.ok:
		var c: PackedFloat64Array=result.coefficients
		var continuous:=true;var bounded:=true
		for i in samples.size()-1:
			var a:=c[i*4];var b:=c[i*4+1];var v:=c[i*4+2];var d:=c[i*4+3]
			if i<samples.size()-2:continuous=continuous and absf(a+b+v+d-c[i*4+7])<0.0001 and absf(3*a+2*b+v-c[i*4+6])<0.0001
			for j in 101:
				var t:=j/100.0;var height:=((a*t+b)*t+v)*t+d;var ground:=lerpf(samples[i].y,samples[i+1].y,t)
				bounded=bounded and absf((3*a*t*t+2*b*t+v)/16)<=0.25001 and absf((6*a*t+2*b)/256)<=0.00801 and height>=ground-15.0001 and height<=ground+3.0001
		check(continuous,"height and tangent continuous at every join")
		check(bounded,"independent dense sampling meets grade curvature and earthwork limits")
	check(not planner.fit(flat,0.25,NAN,15,3).ok,"invalid curvature rejected")
	var impossible:=flat.duplicate();impossible[1].y=150
	var rejected: Dictionary=planner.fit(impossible,0.25,0.008,0,0)
	check(not rejected.ok and not rejected.has("coefficients"),"uncertified route returns no partial construction profile")
	var malformed:=flat.duplicate();malformed[1].z+=1
	check(not planner.fit(malformed,0.25,0.008,15,3).ok,"nonuniform route rejected explicitly")
	var report:={"failures":failures,"fit_us":elapsed,"profile":result,"scope":"Native cubic profile correctness only; not yet terrain construction or driving."}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/road_profile.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("ROAD_PROFILE ",JSON.stringify(report));quit(1 if failures else 0)
