# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)
func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var life:RefCounted=ClassDB.instantiate("NativePlayerLife")
	check(life.restore_storage_snapshot(PackedByteArray()) and life.snapshot().health==100,"old saves start healthy without invented anchor")
	for amount:float in [0,-1,INF,NAN]:check(not life.damage(amount),"invalid damage rejected")
	check(life.set_spawn(Vector3(100,50,100),.2),"valid shelter anchor")
	check(not life.set_spawn(Vector3.INF,0),"invalid shelter leaves previous anchor")
	check(life.damage(18) and life.snapshot().health==82,"zombie damage reduces shared health")
	var copy:RefCounted=ClassDB.instantiate("NativePlayerLife")
	var saved:PackedByteArray=life.capture_storage_snapshot()
	check(saved.size()==56 and copy.restore_storage_snapshot(saved) and copy.snapshot()==life.snapshot(),"health and shelter round trip")
	for offset:int in [8,16,24,32,40]:
		var broken:=saved.duplicate();broken.encode_double(offset,NAN)
		check(not copy.restore_storage_snapshot(broken) and copy.capture_storage_snapshot()==saved,"corrupt snapshot rejected atomically")
	check(life.damage(1000) and life.snapshot().dead and life.snapshot().deaths==1,"fatal damage clamps and records one death")
	check(not life.damage(10) and life.snapshot().deaths==1,"dead player ignores repeated impacts")
	check(copy.restore_storage_snapshot(life.capture_storage_snapshot()) and copy.snapshot().dead,"dead save remains dead until respawn")
	check(copy.respawn() and copy.snapshot().health==100 and not copy.respawn(),"one respawn restores health exactly once")
	check(copy.snapshot().spawn==Vector3(100,50,100) and copy.snapshot().deaths==1,"shelter and death count survive respawn")
	print("PLAYER_LIFE checks=",checks," failures=",failures);quit(1 if failures else 0)
