# SPDX-License-Identifier: 0BSD
extends SceneTree
class Probe extends RefCounted:
	var free:int
	func sample(_path:String)->Dictionary:return {"disk_free_bytes":free}
var checks:=0
var failures:=0
func check(condition:bool,label:String)->void:
	checks+=1
	if not condition:failures+=1
	print("PASS " if condition else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var panel=preload("res://addons/player_runtime/usage_panel.gd").new()
	panel.budgets=JSON.parse_string(FileAccess.get_file_as_string(panel.POLICY))
	panel.probe=Probe.new();panel.paths={"data":""}
	for key:String in ["ram","gpu","free"]:
		var label:=Label.new();var bar:=ProgressBar.new();panel.add_child(label);panel.add_child(bar)
		panel.meters[key]={"label":label,"bar":bar}
	panel.live_note=Label.new();panel.add_child(panel.live_note)
	check(int(panel.budgets.minimum_free_bytes)==2147483648 and int(panel.budgets.free_space_warning_bytes)==10737418240,"2 GiB hard reserve is distinct from 10 GiB warning")
	for row:Array in [[-1,"8daca8"],[0,"ed8f83"],[2147483647,"ed8f83"],[2147483648,"e4bc6b"],[4294967296,"e4bc6b"],[10737418239,"e4bc6b"],[10737418240,"8daca8"],[15032385536,"8daca8"]]:
		panel.probe.free=row[0];panel.refresh_live()
		check(panel.meters.free.label.modulate==Color(row[1]),"free-space state at "+str(row[0]))
	check(panel.meters.free.label.text.contains("warn below 10.00 GiB") and panel.meters.free.label.text.contains("hard reserve 2.00 GiB"),"Usage labels warning versus hard reserve explicitly")
	check(int(panel.budgets.vram_limit_bytes)==4294967296 and int(panel.budgets.redistributable_limit_bytes)==5000000000 and int(panel.budgets.derived_cache_total_bytes)==3221225472,"GPU, content and cache limits are unchanged")
	panel.free();print("DISK_RESERVE checks=",checks," failures=",failures);quit(1 if failures else 0)
