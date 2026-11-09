# SPDX-License-Identifier: 0BSD
extends RefCounted
## Diagnostic CPU marker gaps from a completed render-device frame. These are
## adjacent timestamp differences, not inclusive scopes or current-frame costs.
const MAX_MARKERS:=256
const MAX_GAPS:=8
var previous_frame:=-1

func capture(device:Object)->Dictionary:
	if device==null:return {"available":false,"reason":"no rendering device"}
	var frame:int=device.get_captured_timestamps_frame()
	var count:int=device.get_captured_timestamps_count()
	var result:Dictionary={"available":count>0,"device_frame":frame,"marker_count":count,"truncated":count>MAX_MARKERS}
	if count==0:return result
	if frame==previous_frame:
		result.repeated=true
		return result
	previous_frame=frame
	var limit:=mini(count,MAX_MARKERS)
	var gaps:Array[Dictionary]=[]
	var previous_cpu:int=device.get_captured_timestamp_cpu_time(0)
	var previous_name:String=device.get_captured_timestamp_name(0)
	result.begin_cpu_us=previous_cpu
	var reversed:=0
	for index:int in range(1,limit):
		var current_cpu:int=device.get_captured_timestamp_cpu_time(index)
		var current_name:String=device.get_captured_timestamp_name(index)
		if current_cpu>=previous_cpu:
			gaps.append({"after":previous_name,"before":current_name,"begin_cpu_us":previous_cpu,"cpu_us":current_cpu-previous_cpu})
		else:reversed+=1
		previous_cpu=current_cpu;previous_name=current_name
	result.end_cpu_us=previous_cpu;result.reversed=reversed
	gaps.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.cpu_us>b.cpu_us)
	if gaps.size()>MAX_GAPS:gaps.resize(MAX_GAPS)
	result.largest_cpu_gaps=gaps
	return result
