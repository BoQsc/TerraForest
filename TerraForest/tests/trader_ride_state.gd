# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var store:RefCounted=ClassDB.instantiate("NativeTraderRideState")
	check(store!=null,"native ride state registered")
	if store==null:quit(1);return
	check(store.validate_snapshot(PackedByteArray()) and store.snapshot().phase==0,"old worlds without a service section start idle")
	var state:Dictionary=store.snapshot()
	state.merge({"phase":2,"vehicle":37,"fare":24,"paid":true,"passenger":true,"seated":true,"destination":30,"title":"Settlement 1","driver_position":Vector3(100,20,100),"home":Vector3(90,20,90),"driver_yaw":1.2,"outbound":PackedVector3Array([Vector3(100,20,100),Vector3(100,20,200),Vector3(200,20,200)]),"return_route":PackedVector3Array([Vector3(200,20,200),Vector3(200,20,100),Vector3(100,20,100)]),"cursor":1},true)
	check(store.set_state(state),"paid occupied outbound route validates")
	var saved:PackedByteArray=store.capture_storage_snapshot()
	var copy:RefCounted=ClassDB.instantiate("NativeTraderRideState")
	check(copy.restore_storage_snapshot(saved) and copy.snapshot().passenger and copy.snapshot().paid and copy.snapshot().cursor==1,"paid passenger and route progress round trip without another purchase")
	for phase in [1,3,4,5,6]:
		var trial:=state.duplicate(true);trial.phase=phase;trial.passenger=phase in [3,6]
		check(copy.set_state(trial) and copy.snapshot().phase==phase,"service phase %d round trips"%phase)
	for field in ["vehicle","fare","refund","cursor","phase"]:
		var bad:=state.duplicate(true);bad[field]=-1
		check(not store.set_state(bad) and store.capture_storage_snapshot()==saved,"negative %s rejects without mutation"%field)
	for change in [{"phase":7},{"cursor":2},{"fare":50001},{"refund":50001},{"vehicle":0},{"phase":4,"passenger":true},{"outbound":PackedVector3Array()},{"home":Vector3(NAN,0,0)},{"driver_yaw":INF},{"title":""},{"outbound":PackedVector3Array([Vector3.ONE,Vector3.ONE])}]:
		var bad:=state.duplicate(true);bad.merge(change,true)
		check(not store.set_state(bad) and store.capture_storage_snapshot()==saved,"invalid state rejects atomically: "+str(change.keys()))
	for size in [1,8,95,saved.size()-1]:
		check(not store.restore_storage_snapshot(saved.slice(0,size)) and store.capture_storage_snapshot()==saved,"truncated archive %d rejects atomically"%size)
	for offset in [0,4,88,92]:
		var bad:=saved.duplicate();bad.encode_u32(offset,999)
		check(not store.restore_storage_snapshot(bad),"invalid archive header %d rejects"%offset)
	var excess:=saved.duplicate();excess.append(0)
	check(not store.restore_storage_snapshot(excess),"unconsumed archive suffix rejects")
	check(store.restore_storage_snapshot(PackedByteArray()) and store.snapshot().vehicle==0,"restoring an old world clears another world's reservation")
	state.expedition=true;state.fare=0;state.refund=0;state.paid=true
	for phase:int in [2,3,4,6,7,8]:
		state.phase=phase;state.passenger=true
		check(store.set_state(state) and copy.restore_storage_snapshot(store.capture_storage_snapshot()) and copy.snapshot().expedition and copy.snapshot().phase==phase,"free expedition occupied phase %d survives reload"%phase)
		state.passenger=false
		check(store.set_state(state) and copy.restore_storage_snapshot(store.capture_storage_snapshot()) and not copy.snapshot().passenger,"waiting expedition phase %d survives reload"%phase)
	state.fare=1
	check(not store.set_state(state),"expedition cannot accidentally charge a fare")
	print("TRADER_RIDE_STATE checks=",checks," failures=",failures);quit(1 if failures else 0)
