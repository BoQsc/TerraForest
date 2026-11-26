# SPDX-License-Identifier: 0BSD
extends SceneTree
## Exercises normal preparation; only replaces the child with a read-only menu probe.
class MeasuredLauncher extends "res://launcher.gd":
 var folder:String
 var launch_epoch:String
 var previous_phase:=""
 func _process(delta:float)->void:
  super._process(delta)
  if phase!=previous_phase:
   print("LAUNCH_STAGE ",JSON.stringify({"phase":phase,"milliseconds":Time.get_ticks_usec()/1000.0}))
   previous_phase=phase
  if status!=null and status.text=="Unable to launch TerraForest":get_tree().quit(1)
 func launch_game()->void:
  print("LAUNCH_PREPARED milliseconds=",Time.get_ticks_usec()/1000.0)
  var args:=PackedStringArray(["--path",project_root,"--log-file",folder.path_join("menu.log"),"--max-fps","60","--script","res://tests/world_browser_responsiveness.gd","--","--measure-first-ui","--isolated-render","--check-evidence-dir="+folder,"--launch-start-unix-usec="+launch_epoch])
  game_pid=OS.create_process(engine,args)
  if game_pid<=0:fail("Cannot start the menu probe");return
  status.text="TerraForest is running";get_window().mode=Window.MODE_MINIMIZED
func _initialize()->void:run.call_deferred()
func run()->void:
 var launcher:=MeasuredLauncher.new()
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--check-evidence-dir="):launcher.folder=argument.trim_prefix("--check-evidence-dir=")
  if argument.begins_with("--launch-start-unix-usec="):launcher.launch_epoch=argument.trim_prefix("--launch-start-unix-usec=")
 if launcher.folder.is_empty() or launcher.launch_epoch.is_empty():push_error("Full launch requires admitted evidence and the external start clock");quit(1);return
 root.add_child(launcher)
