# SPDX-License-Identifier: 0BSD
extends RefCounted
## Diagnostic CPU marker gaps from a completed render-device frame. These are
## adjacent timestamp differences, not inclusive scopes or current-frame costs.
const MAX_MARKERS:=256
const MAX_GAPS:=8
var previous_frame:=-1
var gpu_enabled:=OS.get_cmdline_user_args().has("--frame-trace-render-gpu-stages")

func capture(device:Object)->Dictionary:
	var began:int=Time.get_ticks_usec() if gpu_enabled else 0
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
	var gpu_gaps:Array[Dictionary]=[]
	# RenderingDevice's Vulkan driver returns nanoseconds, unlike CPU usec.
	# Keep raw units and the completed device-frame identity; clocks are not aligned.
	var previous_gpu:int=device.get_captured_timestamp_gpu_time(0) if gpu_enabled else 0
	var gpu_reversed:=0
	if gpu_enabled:result.begin_gpu_ns=previous_gpu
	var previous_cpu:int=device.get_captured_timestamp_cpu_time(0)
	var previous_name:String=device.get_captured_timestamp_name(0)
	result.begin_cpu_us=previous_cpu
	var reversed:=0
	for index:int in range(1,limit):
		var current_cpu:int=device.get_captured_timestamp_cpu_time(index)
		var current_name:String=device.get_captured_timestamp_name(index)
		if gpu_enabled:
			var current_gpu:int=device.get_captured_timestamp_gpu_time(index)
			if current_gpu>=previous_gpu:
				gpu_gaps.append({"after":previous_name,"before":current_name,"begin_gpu_ns":previous_gpu,"gpu_ns":current_gpu-previous_gpu})
			else:gpu_reversed+=1
			previous_gpu=current_gpu
		if current_cpu>=previous_cpu:
			gaps.append({"after":previous_name,"before":current_name,"begin_cpu_us":previous_cpu,"cpu_us":current_cpu-previous_cpu})
		else:reversed+=1
		previous_cpu=current_cpu;previous_name=current_name
	result.end_cpu_us=previous_cpu;result.reversed=reversed
	gaps.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.cpu_us>b.cpu_us)
	if gaps.size()>MAX_GAPS:gaps.resize(MAX_GAPS)
	result.largest_cpu_gaps=gaps
	if gpu_enabled:
		gpu_gaps.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.gpu_ns>b.gpu_ns)
		if gpu_gaps.size()>MAX_GAPS:gpu_gaps.resize(MAX_GAPS)
		result.largest_gpu_gaps=gpu_gaps;result.end_gpu_ns=previous_gpu;result.gpu_reversed=gpu_reversed
		result.gpu_available=int(result.begin_gpu_ns)>0 and previous_gpu>0
		result.capture_cpu_us=Time.get_ticks_usec()-began
	return result
