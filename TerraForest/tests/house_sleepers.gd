# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	if not ClassDB.class_exists("NativeZombiePopulation"):GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var store=ClassDB.instantiate("NativeZombiePopulation")
	check(store.initialize(1703,Vector3(800,0,1310)),"authored registry initializes independently of player saves")
	var legacy:PackedByteArray=store.capture_snapshot()
	var anchors:Array=[{"key":101,"position":Vector3(110,12,110),"yaw":0.,"pose":1},{"key":102,"position":Vector3(190,4,110),"yaw":PI,"pose":2},{"key":103,"position":Vector3(801,2,1310),"yaw":0.,"pose":1}]
	var added:Dictionary=store.register_sleepers(anchors)
	check(added.ok and added.added==2 and added.ids==PackedInt64Array([2501,2502,0]),"authored residents obey the initial forty-metre sanctuary")
	var saved:PackedByteArray=store.capture_snapshot()
	check(saved.decode_u32(4)==4 and saved.size()==32+2502*140,"keyed residents use a bounded binary layout")
	check(store.restore_snapshot(saved) and store.capture_snapshot()==saved,"keyed asleep records roundtrip exactly")
	check(store.resident(2501).sleep.decode_u32(0)==1 and store.resident(2502).sleep.decode_u32(0)==2,"seated and lying poses survive registration")
	check(store.register_sleepers(anchors).added==0 and store.capture_snapshot()==saved,"repeated publication cannot duplicate inhabitants")
	var malformed:=anchors.duplicate(true);malformed[1].key=101
	check(not store.register_sleepers(malformed).ok and store.capture_snapshot()==saved,"duplicate batch keys reject atomically")
	for field:String in ["key","position","yaw","pose"]:
		malformed=anchors.duplicate(true);malformed[0][field]="invalid"
		check(not store.register_sleepers(malformed).ok and store.capture_snapshot()==saved,"invalid authored field rejects: "+field)
	malformed=anchors.duplicate(true);malformed[0].position=Vector3(INF,0,0)
	check(not store.register_sleepers(malformed).ok and store.capture_snapshot()==saved,"nonfinite authored coordinates reject")
	var corrupt:=saved.duplicate();corrupt.encode_u64(32+2501*140+132,101)
	check(not store.restore_snapshot(corrupt) and store.capture_snapshot()==saved,"duplicate persisted key cannot replace live population")
	var vitals:PackedByteArray=store.resident(2501).vitals
	check(store.update_resident(2501,Vector3(130,12,110),1.,vitals),"woken resident preserves its authored identity while moving")
	var awake:PackedByteArray=store.capture_snapshot()
	check(store.register_sleepers(anchors).added==0 and store.capture_snapshot()==awake,"republication cannot put an awake resident back to sleep")
	vitals.encode_float(0,0.)
	check(store.update_resident(2501,Vector3(130,12,110),1.,vitals),"dead authored resident is tombstoned")
	var dead:PackedByteArray=store.capture_snapshot()
	check(store.restore_snapshot(dead) and store.register_sleepers(anchors).added==0 and store.capture_snapshot()==dead and store.resident(2501).state==2,"reload and repeated publication cannot resurrect a cleared house")
	check(store.restore_snapshot(legacy) and store.capture_snapshot()==legacy,"opening old population bytes does not invent house sleepers")
	corrupt=saved.duplicate();corrupt.encode_u64(32+132,110)
	check(not store.restore_snapshot(corrupt) and store.capture_snapshot()==legacy,"natural residents cannot masquerade as authored keys")
	var capacity:Array=[]
	for index in 257:capacity.append({"key":10000+index,"position":Vector3(100+index,10,110),"yaw":0.,"pose":1})
	check(not store.register_sleepers(capacity).ok and store.capture_snapshot()==legacy,"oversized registration does not partially publish")
	capacity.resize(256)
	check(store.register_sleepers(capacity).added==256 and store.statistics().slots==2756,"complete authored capacity remains bounded")
	var full:PackedByteArray=store.capture_snapshot()
	check(store.register_sleepers(capacity).added==0 and store.capture_snapshot()==full,"full-capacity replay remains idempotent")
	check(not store.register_sleepers([anchors[0]]).ok and store.capture_snapshot()==full,"capacity exhaustion cannot damage published residents")
	store.restore_snapshot(legacy)
	if "--native-only" in OS.get_cmdline_user_args():finish();return
	var homes=load("res://addons/characters/runtime/house_sleepers.gd")
	var lots:Array=[]
	for id:String in homes.HOMES:
		for rotation in 4:lots.append({"asset":homes.Catalog.asset(id),"origin":Vector3i(300+rotation*50,20,300 if id=="cottage_a2" else 500),"rotation":rotation})
	var planned:Dictionary=homes.plan(lots,1703)
	check(planned.ok and not planned.anchors.is_empty() and planned.anchors==homes.plan(lots,1703).anchors,"authored transforms and selection are deterministic")
	lots.reverse()
	check(homes.plan(lots,1703).anchors==planned.anchors,"lot traversal order cannot change authored identities")
	check(store.register_sleepers(planned.anchors).ok,"all reviewed home anchors fit the native persistence contract")
	check(homes.key(Vector3i(300,20,300),0)!=homes.key(Vector3i(300,21,300),0) and homes.key(Vector3i(300,20,300),0)!=homes.key(Vector3i(300,20,300),1),"stacked and rotated sites retain distinct stable keys")
	var generated:Dictionary=load("res://addons/world_runtime/world_generation_plan.gd").build(1703,29,true,true,"user://generation_plans",load("res://addons/world_runtime/world_recipe.gd").DEFAULTS)
	var actual_lots:Array=[]
	for site:Dictionary in generated.get("sites",[]):actual_lots.append_array(site.lots)
	for lot:Dictionary in actual_lots:
		if homes.HOMES.has(str(lot.asset.get_meta("expansion_id",""))):print("HOME_CANDIDATE ",lot.origin," rotation=",lot.rotation," key=",homes.key(lot.origin,lot.rotation))
	var actual:Dictionary=homes.plan(actual_lots,1703)
	check(generated.get("ok",false) and actual.ok and not actual.anchors.is_empty(),"default production recipe actually contains authored sleepers")
	finish()
func finish()->void:
	print("HOUSE_SLEEPERS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
