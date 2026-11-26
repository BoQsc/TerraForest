# SPDX-License-Identifier: 0BSD
extends SceneTree
const Outdoors=preload("res://addons/structures/outdoor_generation.gd")
var checks:=0
var failures:=0

class Terrain extends Node:
	signal density_batch_ready(result:Dictionary)
	var epoch:=3
	var density_revision:=7
	var stopping:=false
	var requests:Array[int]=[]
	var invalid_on:=0
	var changed_on:=0
	var replaced_on:=0
	func request_density_scan(points:PackedVector3Array,token:int,_depth:int,interpolated:bool)->bool:
		assert(interpolated)
		requests.append(points.size())
		var values:=PackedFloat32Array()
		for point in points:values.append(NAN if point.x>30 else point.y)
		var result:Dictionary={"token":token,"epoch":epoch,"revision":density_revision,"status":"ok","values":values}
		if requests.size()==invalid_on:result.values=PackedFloat32Array()
		_deliver.call_deferred(result)
		return true
	func _deliver(result:Dictionary)->void:
		if requests.size()==changed_on:density_revision+=1
		if requests.size()==replaced_on:epoch+=1
		density_batch_ready.emit(result)
	func reset()->void:
		requests.clear();invalid_on=0;changed_on=0;replaced_on=0;stopping=false

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	var terrain:=Terrain.new();root.add_child(terrain)
	var bounds:Array[AABB]=[]
	# Mixed footprints cross request boundaries; supported, floating and nonfinite
	# candidates exercise indexing independently of the batching implementation.
	for index in 48:
		bounds.append(AABB(Vector3(index,0 if index%3 else 1,0),Vector3(1+index%5,1,1+index%4)))
	var serial:Array[bool]=[]
	for box in bounds:
		var samples:=await Outdoors._density(terrain,Outdoors.support_probes(box))
		var supported:=true
		for index in samples.size():
			if not is_finite(samples[index]) or (samples[index]<0)!=(index%2==0):supported=false
		serial.append(supported)
	var serial_requests:=terrain.requests.size()
	terrain.reset()
	var batch:Dictionary=await Outdoors._support(terrain,bounds)
	check(batch.ok and batch.supported==serial,"batched support matches 48 individual terrain queries exactly")
	check(serial.has(true) and serial.has(false),"comparison includes accepted and rejected support")
	check(terrain.requests.size()>1 and terrain.requests.size()<serial_requests,"multiple bounded requests replace individual-object waits")
	check(terrain.requests.all(func(size:int):return size>0 and size<=4096 and size%2==0),"every request respects the terrain sample limit and paired probes")
	check(batch.samples==terrain.requests.reduce(func(total:int,size:int):return total+size,0),"all support samples are accounted for")
	terrain.reset()
	var empty:Dictionary=await Outdoors._support(terrain,[])
	check(empty.ok and empty.supported.is_empty() and terrain.requests.is_empty(),"empty lot submits no terrain work")
	for mode in ["invalid_on","changed_on","replaced_on"]:
		terrain.reset();terrain.set(mode,2)
		var rejected:Dictionary=await Outdoors._support(terrain,bounds)
		check(not rejected.ok and terrain.requests.size()==2,"partial batch cannot publish after "+mode)
	terrain.reset();terrain.stopping=true
	check(not (await Outdoors._support(terrain,bounds)).ok and terrain.requests.is_empty(),"shutdown cancels support work without submitting another query")
	terrain.reset()
	check(not (await Outdoors._support(terrain,[AABB(Vector3.ZERO,Vector3(30,1,30))])).ok and terrain.requests.is_empty(),"oversized individual support footprint fails without an unfulfillable request")
	terrain.free();await process_frame
	print("OUTDOOR_SUPPORT_BATCHES checks=",checks," failures=",failures);quit(1 if failures else 0)
