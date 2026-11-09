# SPDX-License-Identifier: 0BSD
extends SceneTree
const Trace=preload("res://addons/world_runtime/frame_trace.gd")
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var trace:=Trace.new();root.add_child(trace)
	process_frame.disconnect(trace._begin_process);physics_frame.disconnect(trace._begin_physics)
	RenderingServer.frame_pre_draw.disconnect(trace._begin_draw);RenderingServer.frame_post_draw.disconnect(trace._end_draw)
	trace.set_process(false);trace.set_physics_process(false)
	trace.output="res://reports/frame_trace_test";DirAccess.make_dir_recursive_absolute(trace.output)
	for i in 1300:trace.record({"at_us":i*16667,"frame_ms":16.667,"frame":i,"stages_ms":{}},false)
	var history:=trace.history(1299*16667)
	check(trace.count==Trace.CAPACITY,"ring must remain bounded")
	check(history.front().frame>600 and history.back().frame==1299,"history must retain the newest ten seconds in order")
	check(trace.mark("synthetic",1299*16667),"manual marker accepted")
	var original_size:int=trace.pending.frames.size()
	check(not trace.mark("busy",1299*16667),"overlapping capture must be bounded")
	trace.record({"at_us":1300*16667,"frame_ms":40.0,"frame":1300,"stages_ms":{"test":40.0}},true)
	check(trace.pending.frames.size()==original_size+1,"capture must include post-trigger frames")
	trace.record({"at_us":1500*16667,"frame_ms":16.667,"frame":1500,"stages_ms":{}},false)
	check(trace.pending.is_empty() and trace.writer!=null,"completed capture must go to worker")
	trace.writer.wait_to_finish();trace.writer=null
	var captured=JSON.parse_string(FileAccess.get_file_as_string(trace.output.path_join("trace_00.json")))
	check(captured is Dictionary and captured.trigger=="synthetic" and captured.frames.back().frame==1500,"worker JSON must retain pre/post rows")
	trace.record({"at_us":1501*16667,"frame_ms":50.0,"frame":1501,"stages_ms":{}},true)
	check(trace.pending.is_empty(),"cooldown must suppress automatic trigger storms")
	check(captured.frames.size()==original_size+2,"later ring writes must not mutate saved capture")
	trace.record({"at_us":1299*16667+Trace.COOLDOWN_US+1,"frame_ms":16.667,"frame":2000,"stages_ms":{}},false)
	check(not trace.pending.is_empty() and trace.pending.metadata.outlier_us==1501*16667,"cooldown outliers must be captured from history when cooldown ends")
	trace.pending={};trace.deferred_outlier_us=0
	trace.last_trigger=-Trace.COOLDOWN_US;trace.cadence.clear();trace.cadence_sum=0
	for i in 30:trace.record({"at_us":40000000+i*18000,"frame_ms":18.0,"frame":3000+i,"stages_ms":{}},true)
	check(not trace.pending.is_empty(),"sustained sub-20-ms low FPS must trigger too")
	trace.pending={};trace.deferred_outlier_us=0
	var key:=InputEventKey.new();key.physical_keycode=KEY_G;key.pressed=true
	trace._unhandled_key_input(key)
	check(trace.pending.is_empty(),"recorder must not intercept the gameplay drop key")
	key.physical_keycode=KEY_F12;key.ctrl_pressed=true;key.shift_pressed=true
	trace._unhandled_key_input(key)
	check(not trace.pending.is_empty() and trace.pending.trigger=="player marker","explicit player shortcut must capture")
	trace.pending={}
	for i in 10:
		var result:Dictionary=Trace._write(trace.output.path_join("rotation_%d.json"%(i%Trace.MAX_FILES)),{"serial":i})
		check(result.ok,"rotation must replace its own existing file on Windows")
	trace.free();await process_frame
	check(root.get_node_or_null("WorldSession/FrameTrace")==null,"normal launch must not allocate a recorder")
	print("FRAME_TRACE_TEST failures=",failures);quit(0 if failures==0 else 1)
