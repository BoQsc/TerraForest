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
	# Priority deliberately differs: local coverage dependencies precede more
	# hidden detail. Request membership and coverage remain legacy-equivalent.
	var expected: Dictionary = reference.coverage()
	var covered: Dictionary = planner.coverage(reference.tiles,planned.split_state,reference.visible_cut)
	var hidden: Array[Vector3i] = []
	for key in reference.visible_cut:
		if not expected["keys"].has(key): hidden.append(key)
	check(planned.ok and planned.requested_keys==reference.requested_keys and planned.split_state==reference.split_state and key_set(planned.requests)==key_set(wanted) and planned.requests.size()==wanted.size(),label+" request set and hysteresis match legacy")
	var activation_valid:=true
	var normal_seen:=false
	for key: Vector3i in planned.requests:
		if not planned.activation_keys.has(key): normal_seen=true
		elif normal_seen: activation_valid=false
	for key: Vector3i in planned.activation_keys:
		activation_valid=activation_valid and planned.requests.has(key) and planned.requested_keys.has(key)
	check(activation_valid,label+" activation dependencies form a prefix of existing requested work")
	check(covered.ok and covered["keys"]==expected["keys"] and covered.hidden==hidden and covered.root_coverage==expected.root_coverage and covered.covered_roots==expected.covered_roots and unchanged,label+" coverage, dirty fallback and immutable inputs match legacy")
	var victims: Dictionary = planner.eviction_candidates(reference.tiles,reference.visible_cut,planned.requested_keys)
	var expected_victims := {}
	for key: Vector3i in reference.tiles:
		if key.z!=256 and not reference.visible_cut.has(key) and not reference.requested_keys.has(key): expected_victims[key]=true
	var ordered:=true
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
	check_targeted()
	check_travel_activation()
	check_available()
	check_invalid()
	benchmark()
	finish()

func check_available() -> void:
	var root:=Vector3i(1280,1024,256)
	var target:=Vector3i(1296,1248,16)
	var tiles: Dictionary={target:{"dirty":false}}
	var split: Dictionary={}
	for size in [32,64,128,256]:
		split[Vector3i(target.x/size*size,target.y/size*size,size)]=true
	var result: Dictionary=planner.coverage_available(tiles,split,[])
	check(result.ok and result["keys"]==[target],"ready local tile is visible without absent root or siblings")
	check(result.root_coverage==0 and result.covered_roots.is_empty(),"partial visibility does not report a complete world root")
	tiles[root]={"dirty":false}
	result=planner.coverage_available(tiles,split,[root])
	check(result["keys"]==[root],"existing parent remains until complete replacement is ready")
	tiles[root].dirty=true
	check(planner.coverage_available(tiles,split,[root])["keys"]==[root],"dirty live parent remains during atomic edit publication")
	result=planner.coverage_available(tiles,split,[])
	check(result["keys"]==[target],"dirty hidden parent cannot suppress or replace current local geometry")
	tiles[target].dirty=true
	check(planner.coverage_available(tiles,split,[])["keys"].is_empty(),"dirty hidden local geometry is not exposed")
	# Arrival order adversary: adding clean meshes must never remove coverage
	# already visible, nor select overlapping parents and descendants.
	tiles.clear();split.clear()
	var arrivals: Array[Vector3i]=[]
	for size in [16,32,64,128,256]:
		for z in range(root.y,root.y+256,size):
			for x in range(root.x,root.x+256,size):
				var key:=Vector3i(x,z,size)
				arrivals.append(key)
				if size>16: split[key]=true
	var rng:=RandomNumberGenerator.new();rng.seed=9302026
	for i in range(arrivals.size()-1,0,-1):
		var j:=rng.randi_range(0,i)
		var key: Vector3i=arrivals[i];arrivals[i]=arrivals[j];arrivals[j]=key
	var visible: Array=[]
	var previous: Dictionary={}
	var monotonic:=true
	var disjoint:=true
	for key: Vector3i in arrivals:
		tiles[key]={"dirty":false}
		result=planner.coverage_available(tiles,split,visible)
		visible=result["keys"]
		var cells: Dictionary={}
		for owner: Vector3i in visible:
			for z in range(owner.y,owner.y+owner.z,16):
				for x in range(owner.x,owner.x+owner.z,16):
					var cell:=Vector2i(x,z)
					disjoint=disjoint and not cells.has(cell)
					cells[cell]=true
		for cell in previous: monotonic=monotonic and cells.has(cell)
		previous=cells
	check(monotonic,"341 shuffled arrivals never remove previously covered space")
	check(disjoint,"341 shuffled arrivals never overlap parent and child surfaces")
	check(result.root_coverage==1 and visible.size()==256,"completed root converges to full fine coverage")

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

func check_targeted() -> void:
	var player:=Vector3(960,100,1310)
	var target:=Vector3(1060,70,1310)
	var ordinary: Dictionary=planner.requests(player,true,{}, {},[])
	var aimed: Dictionary=planner.requests_targeted(player,true,target,{}, {},[])
	var retained_all:=true
	for key: Vector3i in ordinary.requested_keys:
		retained_all=retained_all and aimed.requested_keys.has(key)
	check(aimed.ok and retained_all,"brush targeting preserves every player loading request")
	var key:=Vector3i(1056,1296,16)
	check(aimed.requests[0]==key and aimed.activation_keys.has(key),"brush target outside player fine radius receives first activation priority")
	check(key_set(aimed.requests).size()==aimed.requests.size(),"two loading foci do not duplicate jobs")
	check(not planner.requests_targeted(player,true,Vector3(NAN,0,0),{}, {},[]).ok,"nonfinite brush focus rejected")

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

func check_travel_activation() -> void:
	var focus:=Vector3(400,180,470)
	var current: Dictionary=planner.requests_travel(focus,true,Vector3(0,0,30),{}, {},[])
	var plain: Dictionary=planner.requests(focus,true,{}, {},[])
	check(current.ok and current.requests[0]==plain.requests[0],"travel preserves current-position activation priority")
	# Across the 512 m root boundary: ready fine detail remains hidden beneath
	# a parent until its sibling coverage is built.
	var tiles: Dictionary={Vector3i(256,512,256):{"dirty":false},Vector3i(384,512,16):{"dirty":false},Vector3i(400,512,16):{"dirty":false}}
	var planned: Dictionary=planner.requests_travel(focus,true,Vector3(0,0,30),tiles,{},[Vector3i(256,512,256)])
	var bridge:=Vector3i(256,512,128)
	var detail:=Vector3i(432,528,16)
	check(planned.requests.has(bridge) and planned.requests.has(detail) and planned.requests.find(bridge)<planned.requests.find(detail),"ahead activation bridge precedes unrelated hidden fine detail")
	check(not planner.requests_travel(focus,true,Vector3(NAN,0,0),{}, {},[]).ok,"nonfinite travel rejected")
