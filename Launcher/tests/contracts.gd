# SPDX-License-Identifier: 0BSD
extends SceneTree
class IdleLauncher extends "res://launcher.gd":
 func start()->void:
  status.text="Idle test launcher"
var failures:=0
func check(value:bool,label:String)->void:
 print("PASS " if value else "FAIL ",label)
 if not value:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
 var first:=IdleLauncher.new();root.add_child(first)
 check(first.lock.is_listening(),"First launcher owns its checkout lease")
 var duplicate:=IdleLauncher.new();root.add_child(duplicate)
 check(not duplicate.lock.is_listening() and duplicate.details.text.contains("already"),"Second launcher reports the existing owner without launching")
 duplicate.free();first.free()
 var replacement:=IdleLauncher.new();root.add_child(replacement)
 check(replacement.lock.is_listening(),"Closing a launcher releases the lease")
 replacement.free()
 var invalid=load("res://launcher.gd").new()
 invalid.project_root=ProjectSettings.globalize_path("user://missing_source_fixture")
 root.add_child(invalid)
 check(invalid.game_pid<0 and invalid.status.text=="Unable to launch TerraForest","Missing project remains a visible failure without starting gameplay")
 invalid.free()
 var fixture:=ProjectSettings.globalize_path("user://launcher_contract_fixture")
 DirAccess.make_dir_recursive_absolute(fixture)
 FileAccess.open(fixture.path_join("project.godot"),FileAccess.WRITE).store_string("config_version=5")
 var failing=load("res://launcher.gd").new()
 failing.project_root=fixture;failing.engine=fixture.path_join("missing_engine")
 root.add_child(failing)
 var deadline:=Time.get_ticks_msec()+5000
 while failing.worker!=null and Time.get_ticks_msec()<deadline:await process_frame
 check(failing.worker==null and failing.game_pid<0 and failing.status.text=="Unable to launch TerraForest","Failed preparation cannot launch the game")
 check(failing.retry.visible,"Preparation failure leaves a retry action")
 failing.free()
 var pid:=OS.create_process(OS.get_executable_path(),PackedStringArray(["--headless","--version"]))
 check(pid>0,"Native game-process launch returns an owned PID")
 while OS.is_process_running(pid):await process_frame
 check(OS.get_process_exit_code(pid)==0,"Native exit status survives completion polling")
 print("LAUNCHER_CONTRACT failures=",failures)
 quit(0 if failures==0 else 1)
