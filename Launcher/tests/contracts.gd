# SPDX-License-Identifier: 0BSD
extends SceneTree
class IdleLauncher extends "res://launcher.gd":
 var closed:=false
 func start()->void:
  status.text="Idle test launcher"
 func finish_close()->void:closed=true
var failures:=0
func check(value:bool,label:String)->void:
 print("PASS " if value else "FAIL ",label)
 if not value:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
 var first:=IdleLauncher.new();root.add_child(first)
 if DisplayServer.get_name()!="headless":
  await RenderingServer.frame_post_draw
  print("LAUNCHER_FIRST_UI milliseconds=",Time.get_ticks_usec()/1000.0)
 await process_frame;await process_frame
 check(first.lock.is_listening(),"First launcher owns its checkout lease")
 var duplicate:=IdleLauncher.new();root.add_child(duplicate)
 check(not duplicate.lock.is_listening() and duplicate.details.text.contains("already"),"Second launcher reports the existing owner without launching")
 duplicate.free();first.free()
 var replacement:=IdleLauncher.new();root.add_child(replacement)
 await process_frame;await process_frame
 check(replacement.lock.is_listening(),"Closing a launcher releases the lease")
 replacement.free()
 var invalid=load("res://launcher.gd").new()
 invalid.project_root=ProjectSettings.globalize_path("user://missing_source_fixture")
 root.add_child(invalid)
 await process_frame;await process_frame
 check(invalid.game_pid<0 and invalid.status.text=="Unable to launch TerraForest","Missing project remains a visible failure without starting gameplay")
 invalid.free()
 var fixture:=ProjectSettings.globalize_path("user://launcher_contract_fixture")
 DirAccess.make_dir_recursive_absolute(fixture)
 FileAccess.open(fixture.path_join("project.godot"),FileAccess.WRITE).store_string("config_version=5")
 var failing=load("res://launcher.gd").new()
 failing.project_root=fixture;failing.engine=fixture.path_join("missing_engine")
 root.add_child(failing)
 await process_frame;await process_frame
 var deadline:=Time.get_ticks_msec()+5000
 while failing.worker!=null and Time.get_ticks_msec()<deadline:await process_frame
 check(failing.worker==null and failing.game_pid<0 and failing.status.text=="Unable to launch TerraForest","Failed preparation cannot launch the game")
 check(failing.retry.visible,"Preparation failure leaves a retry action")
 failing.free()
 var logged:=IdleLauncher.new();root.add_child(logged)
 await process_frame;await process_frame
 logged.log_path=fixture.path_join("import.log")
 var bad_log:=FileAccess.open(logged.log_path,FileAccess.WRITE)
 bad_log.store_string("SCRIPT ERROR: controlled import failure\n");bad_log.close()
 logged.phase="import";logged.worker=Thread.new()
 logged.worker.start(logged.run_process.bind(PackedStringArray(["--headless","--version"])))
 while logged.worker!=null:await process_frame
 check(logged.game_pid<0 and logged.status.text=="Unable to launch TerraForest" and logged.phase=="import","worker log validation rejects script errors even when the child exits successfully")
 logged.free();DirAccess.remove_absolute(fixture.path_join("import.log"))
 var closing:=IdleLauncher.new();root.add_child(closing)
 await process_frame;await process_frame
 closing.worker=Thread.new();closing.phase="native"
 closing.worker.start(func():OS.delay_msec(100);return 0)
 var close_button:Button
 for node:Node in closing.find_children("*","Button",true,false):
  if node.text=="Close":close_button=node;break
 var sent:=Time.get_ticks_usec()
 var point:=close_button.get_global_rect().get_center()
 for pressed:bool in [true,false]:
  var click:=InputEventMouseButton.new();click.position=point;click.global_position=point;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=pressed;root.push_input(click)
 print("LAUNCHER_CLOSE_INPUT milliseconds=",(Time.get_ticks_usec()-sent)/1000.0)
 check(closing.closing_requested and root.mode==Window.MODE_MINIMIZED,"Close immediately minimizes the launcher while preparation owns its files")
 while closing.worker!=null:await process_frame
 check(closing.closed and closing.game_pid<0 and closing.phase=="native","closed launcher joins its worker without starting import or gameplay")
 closing.free();root.mode=Window.MODE_WINDOWED
 var pid:=OS.create_process(OS.get_executable_path(),PackedStringArray(["--headless","--version"]))
 check(pid>0,"Native game-process launch returns an owned PID")
 while OS.is_process_running(pid):await process_frame
 check(OS.get_process_exit_code(pid)==0,"Native exit status survives completion polling")
 print("LAUNCHER_CONTRACT failures=",failures)
 quit(0 if failures==0 else 1)
