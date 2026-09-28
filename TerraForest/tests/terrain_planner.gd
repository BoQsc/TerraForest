extends SceneTree
const Reference = preload("res://tests/reference_terrain_planner.gd")
var checks := 0
var failures := 0
var planner: RefCounted
var metrics := {}

func check(value: bool, label: String) -> void:
	checks+=1
	if not value: failures+=1
	print(("PASS " if value else "FAIL ")+label)

func _initialize() -> void:
	if not ClassDB.class_exists("NativeTerrainPlanner"):
		GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	run.call_deferred()

func key_set(keys: Array) -> Dictionary:
	var result := {}
	for key in keys: result[key]=true
	return result

func equivalent(reference: RefCounted, label: String) -> void:
	var before_tiles: Dictionary = reference.tiles.duplicate(true)
	var before_split: Dictionary = reference.split_state.duplicate()
	var before_visible: Array[Vector3i] = reference.visible_cut.duplicate()
	var planned: Dictionary = planner.requests(reference.focus,reference.require_collision,reference.tiles,reference.split_state,reference.visible_cut)
	var unchanged: bool = reference.tiles==before_tiles and reference.split_state==before_split and reference.visible_cut==before_visible
	var wanted: Array[Vector3i] = reference.requests()
	var ordered := true
	for i in range(1,planned.requests.size()):
		ordered=ordered and not reference._priority(planned.requests[i],planned.requests[i-1])
	var expected: Dictionary = reference.coverage()
	var covered: Dictionary = planner.coverage(reference.tiles,planned.split_state,reference.visible_cut)
	var hidden: Array[Vector3i] = []
	for key in reference.visible_cut:
		if not expected["keys"].has(key): hidden.append(key)
	check(planned.ok and planned.requested_keys==reference.requested_keys and planned.split_state==reference.split_state and key_set(planned.requests)==key_set(wanted) and planned.requests.size()==wanted.size() and ordered,label+" request set, priorities and hysteresis match legacy")
	check(covered.ok and covered["keys"]==expected["keys"] and covered.hidden==hidden and covered.root_coverage==expected.root_coverage and covered.covered_roots==expected.covered_roots and unchanged,label+" coverage, dirty fallback and immutable inputs match legacy")
	var victims: Dictionary = planner.eviction_candidates(reference.tiles,reference.visible_cut,planned.requested_keys)
	var expected_victims := {}
	for key: Vector3i in reference.tiles:
		if key.z!=256 and not reference.visible_cut.has(key) and not reference.requested_keys.has(key): expected_victims[key]=true
	ordered=true
	for i in range(1,victims["keys"].size()):
		ordered=ordered and reference.tiles[victims["keys"][i-1]].used<=reference.tiles[victims["keys"][i]].used
	check(victims.ok and key_set(victims["keys"])==expected_victims and ordered,label+" eviction preserves visible/requested/root tiles and LRU ordering")

func run() -> void:
	check(ClassDB.class_exists("NativeTerrainPlanner"),"native terrain planner registered")
	if failures: finish();return
	planner=ClassDB.instantiate("NativeTerrainPlanner")
	var reference := Reference.new()
	reference.focus=Vector3(960,110,1310)
	equivalent(reference,"empty startup")
	var random := RandomNumberGenerator.new()
	random.seed=9282026
	for step in range(36):
		reference.focus=Vector3(random.randf_range(-200,2200),random.randf_range(0,700),random.randf_range(-200,2200))
		reference.require_collision=step%2==0
		var old_wanted: Array[Vector3i] = reference.requests()
		for key in old_wanted:
			if random.randf()<0.75: reference.tiles[key]={"dirty":random.randf()<0.25,"used":step*100+random.randi_range(0,99)}
		reference.visible_cut.clear()
		for key: Vector3i in reference.tiles:
			if random.randf()<0.1: reference.visible_cut.append(key)
		equivalent(reference,"seeded travel %d" % step)
	check_boundaries()
	check_invalid()
	benchmark()
	finish()

func check_boundaries() -> void:
	var reference := Reference.new()
	var parent := Vector3i(0,0,256)
	reference.tiles[parent]={"dirty":true,"used":0}
	reference.split_state[parent]=true
	reference.visible_cut=[parent]
	var live: Dictionary = planner.coverage(reference.tiles,reference.split_state,reference.visible_cut)
	check(live["keys"].has(parent),"dirty visible tile remains valid coverage before edit publication")
	reference.visible_cut.clear()
	check(not planner.coverage(reference.tiles,reference.split_state,reference.visible_cut)["keys"].has(parent),"dirty hidden parent cannot resurrect stale geometry")
	for child in reference._children(Vector3i(0,0,32)): reference.tiles[child]={"dirty":false,"used":0}
	check(planner.coverage(reference.tiles,reference.split_state,reference.visible_cut)["keys"].size()==0,"partial world root cannot expose an incomplete cut")
	for z in range(0,2048,16):
		for x in range(0,2048,16):
			if x<2000 and z<2000: reference.tiles[Vector3i(x,z,16)]={"dirty":false,"used":0}
	var covered: Dictionary = planner.coverage(reference.tiles,{},[])
	check(covered.root_coverage==64 and covered["keys"].size()==15625,"complete fine coverage clips excluded edge children without holes")
	var legacy: Dictionary = reference.coverage()
	check(covered["keys"]==legacy["keys"],"full fine-world cut matches legacy ordered traversal")
	var split_parent := Vector3i(0,0,32)
	var split := {split_parent:true}
	var hysteresis: Dictionary = planner.requests(Vector3(90,100,0),true,{},split,[])
	var fresh: Dictionary = planner.requests(Vector3(90,100,0),true,{}, {},[])
	check(hysteresis.split_state[split_parent] and not fresh.split_state[split_parent],"prior split remains inside the 30 percent hysteresis band")
	var flight: Dictionary = planner.requests(Vector3(16,1000,16),false,{}, {},[])
	var walking: Dictionary = planner.requests(Vector3(16,1000,16),true,{}, {},[])
	check(flight.requests.size()<walking.requests.size(),"flight altitude reduces refinement while collision mode retains ground coverage")

func check_invalid() -> void:
	check(not planner.requests(Vector3(NAN,0,0),true,{}, {},[]).ok,"nonfinite focus rejected")
	check(not planner.requests(Vector3.ZERO,true,{Vector3i(1,0,16):{"dirty":false}}, {},[]).ok,"unaligned terrain tile rejected")
	check(not planner.coverage({Vector3i(0,0,8):{"dirty":false}}, {},[]).ok,"unsupported tile size rejected")
	check(not planner.coverage({Vector3i(2048,0,16):{"dirty":false}}, {},[]).ok,"out-of-domain tile rejected")
	check(not planner.coverage({Vector3i(0,0,16):{"dirty":1}}, {},[]).ok,"malformed dirty flag rejected")
	check(not planner.coverage({}, {Vector3i(0,0,32):1},[]).ok,"malformed hysteresis flag rejected")
	check(not planner.coverage({}, {},[Vector3.ZERO]).ok,"malformed visible key rejected")
	check(not planner.eviction_candidates({Vector3i(0,0,16):{"dirty":false,"used":"bad"}},[],{}).ok,"malformed eviction timestamp rejected")
	var tile := Vector3i(0,0,16)
	check(planner.eviction_candidates({tile:{"dirty":false,"used":0}},[],{tile:false})["keys"].is_empty(),"requested-key membership protects eviction independently of stored boolean value")
	var excess: Array = []
	excess.resize(21825)
	check(not planner.coverage({}, {},excess).ok,"oversized planner input rejected before traversal")

func benchmark() -> void:
	var reference := Reference.new()
	reference.focus=Vector3(960,110,1310)
	var wanted: Array[Vector3i] = reference.requests()
	for i in range(wanted.size()):
		if i%3!=0: reference.tiles[wanted[i]]={"dirty":i%7==0,"used":i}
	reference.visible_cut.assign(reference.coverage()["keys"])
	var native_times: Array[float] = []
	var legacy_times: Array[float] = []
	for i in range(80):
		var begin := Time.get_ticks_usec()
		reference.requests()
		reference.coverage()
		legacy_times.append(float(Time.get_ticks_usec()-begin)/1000.0)
		begin=Time.get_ticks_usec()
		var plan: Dictionary = planner.requests(reference.focus,true,reference.tiles,reference.split_state,reference.visible_cut)
		planner.coverage(reference.tiles,plan.split_state,reference.visible_cut)
		native_times.append(float(Time.get_ticks_usec()-begin)/1000.0)
	native_times.sort()
	legacy_times.sort()
	metrics={"scope":"Matched headless request + coverage CPU calls, 80 samples; excludes scene publication, backend locks and rendering.","tiles":reference.tiles.size(),"native_median_ms":native_times[40],"native_p95_ms":native_times[76],"legacy_median_ms":legacy_times[40],"legacy_p95_ms":legacy_times[76]}
	print("PLANNER_TIMING ",JSON.stringify(metrics))

func finish() -> void:
	planner=null
	DirAccess.make_dir_recursive_absolute("res://reports")
	var result := {"checks":checks,"failures":failures,"timing":metrics}
	var file := FileAccess.open("res://reports/terrain_planner.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("TERRAIN_PLANNER_RESULT ",JSON.stringify(result))
	quit(1 if failures else 0)
