# SPDX-License-Identifier: 0BSD
extends SceneTree
const Probe=preload("res://tests/destruction_load_probe.gd")
class Source extends RefCounted:
	signal changed(value:Variant)
class Receiver extends RefCounted:
	var identity:int
	var received:Array
	func accept(value:Variant)->void:received.append([identity,value])
var label:="diagnostic_contract"
var failures:=0
func check(ok:bool,message:String)->void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func _initialize()->void:
	var source:=Source.new();var first:=Receiver.new();var second:=Receiver.new()
	var received:Array=[];first.identity=1;second.identity=2;first.received=received;second.received=received
	source.changed.connect(first.accept);source.changed.connect(second.accept)
	var probe:=Probe.new();probe.driver=self
	probe.profile_publication(source,"changed",1,"fixture")
	source.changed.emit(42)
	check(probe.failures.is_empty() and received==[[1,42],[2,42]],"multiple synchronous subscribers retain their identity, payload and order")
	check(probe.publication_profiles.size()==2 and probe.publication_profiles[0].phase==label,"each original callback produces separate attribution")
	probe.restore_publication();source.changed.emit(71)
	check(received==[[1,42],[2,42],[1,71],[2,71]] and probe.publication_profiles.size()==2 and source.changed.is_connected(first.accept) and source.changed.is_connected(second.accept),"restoration removes observers and retains every original subscriber")
	source.changed.disconnect(first.accept);source.changed.disconnect(second.accept)
	print("DESTRUCTION_PUBLICATION_PROBE checks=3 failures=",failures)
	quit(1 if failures else 0)
