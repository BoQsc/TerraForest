extends SceneTree

var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var planner:RefCounted=ClassDB.instantiate("NativeTerrainPlanner")
	var focus:=Vector3(300,60,300)
	var points:=PackedVector3Array()
	var original:Dictionary=planner.requests_navigation(focus,true,Vector3.ZERO,Vector3.INF,points,{}, {}, [],true,true)
	var explicit:Dictionary=planner.requests_navigation(focus,true,Vector3.ZERO,Vector3.INF,points,{}, {}, [],true,true,Vector3.INF,1.0)
	check(original==explicit,"disabled view preserves exact existing request order and cut")
	var view:=Vector3(1500,500,1500)
	var overview:Dictionary=planner.requests_navigation(focus,true,Vector3.ZERO,Vector3.INF,points,{}, {}, [],true,true,view,1.0)
	check(overview.ok and overview.requested_keys.has(Vector3i(1408,1408,128)),"render-only camera refines distant terrain")
	check(overview.activation_keys==original.activation_keys,"render view does not move immediate collision activation")
	var retains:=true
	for key:Vector3i in original.requested_keys:retains=retains and overview.requested_keys.has(key)
	check(retains,"player collision and travel detail survive remote view requests")
	var roots:=0
	for key:Vector3i in overview.requested_keys:
		if key.z==256:roots+=1
	check(roots==64,"every world root remains requested at all view distances")
	var high:Dictionary=planner.requests_navigation(focus,true,Vector3.ZERO,Vector3.INF,points,{}, {}, [],true,true,Vector3(1500,3000,1500),1.0)
	check(high.requested_keys==original.requested_keys,"high overview does not expand full-resolution world residency")
	var zoomed:Dictionary=planner.requests_navigation(focus,true,Vector3.ZERO,Vector3.INF,points,{}, {}, [],true,true,view,2.0)
	check(zoomed.requested_keys.size()>overview.requested_keys.size(),"projection scale increases visual detail independently")
	check(not planner.requests_navigation(focus,true,Vector3.ZERO,Vector3.INF,points,{}, {}, [],true,true,Vector3(NAN,0,0),1.0).ok,"invalid camera rejects before publication")
	check(not planner.requests_navigation(focus,true,Vector3.ZERO,Vector3.INF,points,{}, {}, [],true,true,view,100.0).ok,"projection budget rejects unbounded refinement")
	var tiles:Dictionary={};var visible:Array=[]
	for key:Vector3i in overview.requested_keys:
		if key.z==256:tiles[key]={"dirty":false,"used":0};visible.append(key)
	var pending:Dictionary=planner.requests_navigation(focus,true,Vector3.ZERO,Vector3.INF,points,tiles,{},visible,true,true,view,1.0)
	check(pending.coverage.root_coverage==64 and pending.coverage.keys.size()==64 and pending.coverage.hidden.is_empty(),"zoom refinement retains complete old coarse coverage until ready")
	var timings:=[]
	for position:Vector3 in [Vector3.INF,view,Vector3(1500,3000,1500)]:
		var begin:=Time.get_ticks_usec()
		for iteration in 100:planner.requests_navigation(focus,true,Vector3.ZERO,Vector3.INF,points,tiles,{},visible,true,true,position,1.0)
		timings.append((Time.get_ticks_usec()-begin)/100000.0)
	print("TERRAIN_VIEW_PLANNER failures=",failures," mean_ms=",timings," request_counts=",[original.requested_keys.size(),overview.requested_keys.size(),high.requested_keys.size()])
	quit(1 if failures else 0)
