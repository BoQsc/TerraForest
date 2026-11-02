# SPDX-License-Identifier: 0BSD
extends SceneTree
var output:String
var slot:String
var generate:=false
var started:=0
var previous:=0
var stages:Dictionary={}
var source_hash:String
var profile:=false
var through_control:=false
var measured_game:Node
var work:Array[Dictionary]=[]
var stream_stages:Dictionary={}
var timeline:Array[Dictionary]=[]
var next_sample:=0
func _initialize()->void:
 root.set_flag(Window.FLAG_NO_FOCUS,true)
 ProjectSettings.set_setting("terraforest/offscreen_session",true)
 node_added.connect(func(node:Node):
  if node.scene_file_path=="res://demo/world.tscn":
   ProjectSettings.set_setting("terraforest/offscreen_session",true)
   if through_control and node.get_viewport()==root:
    var args:=PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args()))
    args.append("--entry-fly-in")
    ProjectSettings.set_setting("terraforest/session_arguments",args))
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--benchmark-output="):output=arg.trim_prefix("--benchmark-output=")
  if arg.begins_with("--benchmark-slot="):slot=arg.trim_prefix("--benchmark-slot=")
  if arg=="--benchmark-generate":generate=true
  if arg=="--benchmark-profile":profile=true
  if arg=="--benchmark-through-control":through_control=true
 run.call_deferred()
func wait_for(predicate:Callable,seconds:int)->bool:
 var deadline:=Time.get_ticks_msec()+seconds*1000
 while not predicate.call() and Time.get_ticks_msec()<deadline:
  if is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn":
   var game=current_scene
   game.app_focused=true
   if profile and game!=measured_game:
    measured_game=game
    game.terrain.work_measured.connect(func(row:Dictionary):work.append(row))
    game.terrain.stage_measured.connect(func(label:String,ms:float):stream_stages[label]=float(stream_stages.get(label,0))+ms)
   if profile and game.startup_complete and Time.get_ticks_msec()>=next_sample:
    next_sample=Time.get_ticks_msec()+1000
    timeline.append({"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"state":preload("res://addons/world_runtime/loading_diagnostics.gd").snapshot(game)})
   var stage:String=game.startup_stage if not game.startup_complete else game.loading_stage_text
   var now:=Time.get_ticks_usec()
   if previous>0:stages[stage]=float(stages.get(stage,0))+(now-previous)/1000.0
   previous=now
  await process_frame
 return predicate.call()
func run()->void:
 if output.is_empty() or not slot.begins_with("StartupBench_"):quit(2);return
 var path:="user://worlds/"+slot+".trw"
 if generate==FileAccess.file_exists(path):quit(2);return
 source_hash=FileAccess.get_sha256(path) if not generate else ""
 change_scene_to_file("res://demo/worlds.tscn");await scene_changed
 if not await wait_for(func():return not current_scene.library.loading,60):quit(1);return
 var browser=current_scene
 started=Time.get_ticks_usec()
 if generate:
  browser.name_field.text=slot;browser.seed_field.value=1703;browser.world_tabs.current_tab=1
  browser.generate_button.pressed.emit()
 else:
  var command:Dictionary=preload("res://demo/world_launch.gd").command(slot,false,29,1703,true)
  if not "--benchmark-normal-load" in OS.get_cmdline_user_args():command.args.append("--snapshot-readonly")
  if profile:command.args.append("--profile-owned-regions")
  if "--benchmark-whole-landscape" in OS.get_cmdline_user_args():command.args.append("--whole-landscape-readiness")
  browser._open_game(command.args)
 var ready:bool=await wait_for(func():return is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn" and current_scene.startup_complete and not current_scene.loading_active,600)
 var elapsed:=(Time.get_ticks_usec()-started)/1000.0
 var result:Dictionary={"ok":ready,"generate":generate,"slot":slot,"first_ready_ms":elapsed,"observed_stage_ms":stages,"scope":"Normal browser recipe; offscreen 1920x1080 60 FPS; first loading barrier release, before intro completion. All normal actors enabled."}
 if is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn":
  var game=current_scene
  result.startup=game.startup_timings
  result.resources=root.get_node("WorldSession").stage_timings
  result.readiness=preload("res://addons/world_runtime/loading_diagnostics.gd").snapshot(game)
  if ready:
   if through_control:
    var controlled:bool=await wait_for(func():return not game.loading_active and not game.waiting_spawn and not game.needs_floor_spawn and not game.player_view.entry.pending and not game.player_view.entry.blocks_actions(),60)
    result.controllable_ms=(Time.get_ticks_usec()-started)/1000.0
    result.entry={"starts":game.player_view.entry.starts,"wake_starts":game.player_view.entry.wake_starts,"controlled":controlled}
    var expected_waking:bool=game.player_view.entry.wake_starts==1 or "--benchmark-normal-load" in OS.get_cmdline_user_args()
    ready=ready and controlled and game.player_view.entry.starts==1 and expected_waking
   game.set_physics_process(false)
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png(output.path_join("ready.png"))
   if "--benchmark-observe" in OS.get_cmdline_user_args():await observe(game,result)
  game.shutdown_requested=true
  var closed:bool=await game.terrain.shutdown_after_edits()
  result.shutdown_ok=closed
  result.ok=ready and closed and result.get("observation_ok",true)
  game.free();await process_frame
 if profile:result.profile={"work":work,"stream_stage_ms":stream_stages,"timeline":timeline}
 result.normal_load=not generate and "--benchmark-normal-load" in OS.get_cmdline_user_args()
 result.observation_after_control=through_control
 if not generate:
  result.source_unchanged=source_hash==FileAccess.get_sha256(path)
  if not result.normal_load:result.ok=result.ok and result.source_unchanged
 result.mouse_captures=preload("res://addons/world_runtime/mouse_ownership.gd").captures
 result.ok=result.ok and result.mouse_captures==0
 FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
 print("STARTUP_BENCHMARK ok=",result.ok," first_ready_ms=",elapsed)
 quit(0 if result.ok else 1)

func observe(game:Node,result:Dictionary)->void:
 var local:Dictionary={}
 if game.ecosystem.has_method("local_coverage_status"):
  local.forest=game.ecosystem.local_coverage_status(game.player.global_position)
  local.boulders=game.ground_cover.boulders.local_coverage_status(game.player.global_position)
 var bounds:=AABB(game.player.global_position-Vector3(2,2,2),Vector3(4,5,4))
 local.collision=game.terrain.is_collision_region_ready(bounds) and game.structures.is_collision_region_ready(bounds) and game.vegetation.is_collision_region_ready(bounds)
 result.local_at_release=local
 result.observation_ok=local.collision and local.get("forest",{"ready":true}).ready and local.get("boulders",{"ready":true}).ready
 var camera:Camera3D=game.camera
 var pose:=camera.global_transform
 camera.global_position+=Vector3(0,80,0)
 camera.look_at(game.player.global_position+Vector3(200,0,200))
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(output.path_join("landscape_at_release.png"))
 camera.global_transform=pose
 var frames:Array[float]=[];var full_ms:=-1.0;var begin:=Time.get_ticks_usec();var prior:=begin
 while Time.get_ticks_usec()-begin<20000000:
  await process_frame
  var now:=Time.get_ticks_usec();frames.append((now-prior)/1000.0);prior=now
  if full_ms<0 and game.ecosystem.coverage_status().ready and game.ground_cover.boulders.coverage_status().ready:
   full_ms=(now-begin)/1000.0
 frames.sort()
 result.background={"full_landscape_after_release_ms":full_ms,"observation_ms":(Time.get_ticks_usec()-begin)/1000.0,"frame_p95_ms":frames[int(frames.size()*.95)],"frame_max_ms":frames.back(),"frames":frames.size()}
