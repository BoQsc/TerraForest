# SPDX-License-Identifier: 0BSD
extends SceneTree
const Trace=preload("res://addons/player_runtime/destruction_trace.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
	var trace=Trace.new()
	check(trace.trigger(1,1,10,100)=="" and trace.sample(12,300).is_empty(),"disabled recorder allocates no event records")
	trace.enabled=true
	for id in range(1,257):trace.trigger(7,id,10,100)
	check(trace.events.size()==256 and trace.dropped==0,"entire 256-barrel trigger burst fits")
	trace.trigger(7,1,20,1000)
	check(trace.events["7:1"].trigger_tick==10,"repeated ignition cannot restart the deadline")
	check(trace.trigger(7,257,20,1000)=="" and trace.dropped==1,"overflow is explicit and cannot evict a pending event")
	trace.admitted("7:1",42,15,200)
	trace.blocks_complete("7:1",16,250)
	trace.terrain_complete(42,17,300,{"worker_queue_ms":4.0})
	var first:Dictionary=trace.sample(17,350)
	check(first.pending==255 and first.deadline_misses==256,"delayed admission and queued triggers all miss the original deadline")
	check(first.oldest_age_us==250,"queue age starts at trigger rather than admission")
	var before:int=first.transitions.size()
	trace.sample(18,400)
	check(first.transitions.size()==before and trace.missed==256,"sampling transfers immutable transitions and counts each missed event once")
	trace.reset();trace.trigger(8,1,20,500);trace.admitted("8:1",43,20,500)
	trace.blocks_complete("8:1",21,600);trace.terrain_complete(43,21,600,{})
	var timely:Dictionary=trace.sample(21,610)
	check(timely.pending==0 and timely.deadline_misses==0,"next-tick store and terrain completion is recorded separately from full publication proof")
	trace.reset();trace.trigger(8,2,20,500);trace.admitted("8:2",44,20,500)
	trace.blocks_complete("8:2",21,600);trace.terrain_complete(44,21,600,{})
	check(trace.sample(24,900).deadline_misses==0,"delayed draw does not rewrite the actual completion tick")
	trace.reset();trace.trigger(9,1,30,700)
	for i in 2050:trace._record(trace.events["9:1"],"diagnostic",30,700)
	check(trace.transitions.size()==Trace.TRANSITION_LIMIT and trace.dropped>0,"transition overflow is bounded and reported")
	trace.reset();check(trace.events.is_empty() and trace.tickets.is_empty() and trace.transitions.is_empty(),"world reset releases diagnostic state")
	print("DESTRUCTION_TRACE failures=",failures);quit(1 if failures else 0)
