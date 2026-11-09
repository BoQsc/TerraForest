# SPDX-License-Identifier: 0BSD
extends SceneTree
const Trace=preload("res://addons/world_runtime/frame_trace.gd")
const RenderTrace=preload("res://addons/world_runtime/render_trace.gd")
class MarkerDevice extends RefCounted:
	var frame:=7
	var count:=5
	var last_index:=-1
	var stamps:=PackedInt64Array([100,110,700,699,1100])
	func get_captured_timestamps_frame()->int:return frame
	func get_captured_timestamps_count()->int:return count
	func get_captured_timestamp_cpu_time(index:int)->int:
		last_index=maxi(last_index,index)
		return stamps[index] if index<stamps.size() else 1100+index
	func get_captured_timestamp_name(index:int)->String:return "marker_%d"%index
class ProcessOwner extends Node:
	var sample:Dictionary={"available":true,"started_us":100,"ended_us":200,"process_us":100}
	func process_frame_profile()->Dictionary:return sample.duplicate()
class ProfileFlag extends RefCounted:
	var profiling_enabled:=false
class StageSource extends RefCounted:
	signal stage_measured(label:String,milliseconds:float)
class ProfileHost extends Node:
	var terrain:=StageSource.new()
	var zombies:=ProfileFlag.new()
	var ground_cover:=ProfileFlag.new()
	var vegetation:Dictionary={"renderer":ProfileFlag.new()}
	var structures:Dictionary={"blocks":null}
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func _initialize()->void:run.call_deferred()
func run()->void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var render_trace:=RenderTrace.new();var device:=MarkerDevice.new()
	check(not render_trace.capture(null).available,"headless rendering remains explicitly unavailable")
	var render_sample:Dictionary=render_trace.capture(device)
	check(render_sample.device_frame==7 and render_sample.begin_cpu_us==100 and render_sample.end_cpu_us==1100,"completed render frame and absolute CPU timestamps remain explicit")
	check(render_sample.reversed==1 and render_sample.largest_cpu_gaps[0].cpu_us==590,"reversed timestamps are omitted rather than reported as negative work")
	check(render_trace.capture(device).repeated,"a stale device frame does not duplicate marker work")
	device.frame+=1;device.count=1000
	render_sample=render_trace.capture(device)
	check(render_sample.truncated and device.last_index==RenderTrace.MAX_MARKERS-1 and render_sample.largest_cpu_gaps.size()==RenderTrace.MAX_GAPS,"marker reads and retained gaps stay bounded")
	var trace:=Trace.new();root.add_child(trace)
	var owner:=ProcessOwner.new()
	trace.process_started=90;trace.process_finished=210
	check(trace.native_process_sample(owner).current,"native timing is current only inside the retained process window")
	trace.process_started=201;trace.process_finished=310
	check(not trace.native_process_sample(owner).current,"stale native samples remain explicit rather than attributed to the next frame")
	owner.sample.started_us=250;owner.sample.ended_us=240
	check(not trace.native_process_sample(owner).current,"reversed native sample intervals reject current-frame attribution")
	owner.sample={"available":false}
	check(not trace.native_process_sample(owner).current and not trace.native_process_sample(null).available,"disabled or absent native owners do not become zero-cost samples")
	owner.free()
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld");root.add_child(blocks)
	check(not blocks.is_process_profiling_enabled() and not blocks.process_frame_profile().available,"block process profiling defaults off")
	var block_snapshot:PackedByteArray=blocks.capture_snapshot()
	blocks.set_process_profiling_enabled(true)
	await process_frame;await process_frame
	var block_profile:Dictionary=blocks.process_frame_profile()
	var phase_sum:int=block_profile.horizon_us+block_profile.residency_us+block_profile.upload_us+block_profile.collision_us+block_profile.occlusion_us
	check(block_profile.available and block_profile.ended_us>=block_profile.started_us and block_profile.process_us==phase_sum,"native block phase intervals partition one complete measured callback")
	check(blocks.capture_snapshot()==block_snapshot,"native timing preserves authoritative block data")
	blocks.set_process_profiling_enabled(false)
	check(not blocks.process_frame_profile().available and blocks.process_frame_profile().started_us==0,"disabling native block timing invalidates the retained interval")
	var late_host:=ProfileHost.new();root.add_child(late_host)
	trace.attach(late_host)
	check(not trace.previous_profiling.has("blocks"),"trace can attach before cooperative startup creates blocks")
	late_host.structures.blocks=blocks;trace._begin_process()
	check(blocks.is_process_profiling_enabled(),"late-created block owner receives profiling before its next process callback")
	trace.detach()
	check(not blocks.is_process_profiling_enabled(),"detach restores late-created block owner's original profiling state")
	blocks.set_process_profiling_enabled(true);trace.attach(late_host);trace.detach()
	check(blocks.is_process_profiling_enabled(),"detach preserves a pre-existing block profiling request")
	late_host.free()
	blocks.free()
	for class_name_text:String in ["NativeModelHorizon","NativeResidentLights"]:
		var provider:Node=ClassDB.instantiate(class_name_text)
		check(not provider.process_frame_profile().available,"unconfigured "+class_name_text+" reports unavailable timings")
		provider.free()
	process_frame.disconnect(trace._begin_process);physics_frame.disconnect(trace._begin_physics)
	RenderingServer.frame_pre_draw.disconnect(trace._begin_draw);RenderingServer.frame_post_draw.disconnect(trace._end_draw)
	trace.set_process(false);trace.set_physics_process(false)
	trace._reset_physics_tail()
	trace.physics_tail_started=100;trace.physics_tail_work=PackedInt64Array([1000,500])
	trace._finish_physics_tail(250,PackedInt64Array([2000,600]))
	check(trace.physics_tail_us==150 and trace.physics_tail_segments==1 and trace.physics_tail_cycles==1000 and trace.physics_tail_cpu_us==100,"post-callback physics gap retains elapsed and thread work separately")
	trace._finish_physics_tail(900,PackedInt64Array([3000,700]))
	check(trace.physics_tail_us==150 and trace.physics_tail_segments==1,"closed gap cannot absorb drawing, frame limiting or the next signal twice")
	trace.physics_tail_started=300;trace.physics_tail_work=PackedInt64Array([2000,600])
	trace._finish_physics_tail(475,PackedInt64Array([2500,600]))
	check(trace.physics_tail_us==325 and trace.physics_tail_segments==2 and trace.physics_tail_cycles==1500 and trace.physics_tail_cpu_us==100,"catch-up steps accumulate each closed gap including valid zero CPU deltas")
	trace.physics_tail_started=500;trace.physics_tail_work=PackedInt64Array()
	trace._finish_physics_tail(600,PackedInt64Array())
	check(trace.physics_tail_us==425 and trace.physics_tail_cycles==-1 and trace.physics_tail_cpu_us==-1,"unavailable thread counters preserve wall time without inventing zero CPU work")
	trace.physics_tail_started=800;trace._finish_physics_tail(700,PackedInt64Array())
	check(trace.physics_tail_us==425 and trace.physics_tail_segments==3 and trace.physics_tail_started==0,"reversed gap is rejected and cannot leak into a later frame")
	trace._reset_physics_tail()
	check(trace.physics_tail_us==0 and trace.physics_tail_segments==0 and trace.physics_tail_cycles==0,"new rendered frame must not repeat earlier post-callback work")
	trace.output="res://reports/frame_trace_test";DirAccess.make_dir_recursive_absolute(trace.output)
	check(trace._main_thread_work().size()==2,"native main-thread counters are available in the runtime fixture")
	var worker:=Thread.new();worker.start(trace._main_thread_work)
	var other_thread:PackedInt64Array=worker.wait_to_finish()
	check(other_thread.is_empty(),"worker callbacks must not be subtracted from main-thread counters")
	var measured:Dictionary={}
	Trace.add_work(measured,"draw",PackedInt64Array([100,1000]),PackedInt64Array([300,16625]))
	check(measured.draw_cycles==200 and measured.draw_thread_cpu_ms==15.625,"phase counters retain raw cycles and separately quantized CPU time")
	for pair:Array in [[[],[]],[[-1,-1],[-1,-1]],[[300,2000],[100,1000]]]:
		var unknown:Dictionary={}
		Trace.add_work(unknown,"draw",PackedInt64Array(pair[0]),PackedInt64Array(pair[1]))
		check(unknown.is_empty(),"missing, unsupported and reversed counters must not become zero-work evidence")
	var partial:Dictionary={}
	Trace.add_work(partial,"physics",PackedInt64Array([100,-1]),PackedInt64Array([100,-1]))
	check(partial.physics_cycles==0 and not partial.has("physics_thread_cpu_ms"),"a valid zero delta remains distinct from an unavailable CPU-time counter")
	var first_query:Dictionary={"planning_us":50000,"query_profile":{"support_us":49000}}
	trace.capture_navigation(first_query,{"planning":50000})
	first_query.query_profile.support_us=0
	trace.capture_navigation({"planning_us":0},{"planning":0})
	var ticks:Dictionary=trace.take_navigation_samples()
	check(ticks.samples.size()==2 and ticks.samples[0].navigation.query_profile.support_us==49000 and ticks.samples[1].navigation.planning_us==0,"catch-up physics ticks must retain the earlier slow query as an immutable sample")
	check(trace.take_navigation_samples().samples.is_empty(),"rendered frames must not repeat prior physics samples")
	for i in Trace.NAVIGATION_SAMPLE_LIMIT+2:trace.capture_navigation({}, {})
	var bounded:Dictionary=trace.take_navigation_samples()
	check(bounded.samples.size()==Trace.NAVIGATION_SAMPLE_LIMIT and bounded.dropped==2,"unusual catch-up workloads must remain bounded and report omitted samples")
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
	FileAccess.open("res://reports/frame_trace.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}))
	print("FRAME_TRACE_TEST failures=",failures);quit(0 if failures==0 else 1)
