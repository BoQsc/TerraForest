# SPDX-License-Identifier: 0BSD
extends SceneTree
const Bake=preload("res://tools/tool_drop_bake.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var state:=Bake.snapshot()
	if Bake.current(state):print("TOOL_DROPS current; bake skipped");quit();return
	if "--check" in OS.get_cmdline_user_args():push_error("Tool drop meshes are stale; run tools/bake_tool_drops.gd");quit(1);return
	var view=preload("res://addons/player_runtime/tool_view.gd").new();root.add_child(view)
	var outputs:Dictionary={};var triangles:Dictionary={}
	for item:int in Bake.IDS:
		var mesh:=Bake.build(view,item)
		if mesh==null:push_error("No current tool geometry for %d"%item);view.free();quit(1);return
		var path:="res://addons/player_runtime/art/drops/%d.res"%item
		if ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)!=OK:view.free();quit(1);return
		outputs[path]=FileAccess.get_sha256(path);triangles[str(item)]=mesh.get_meta("source_triangles")
	if state!=Bake.snapshot():push_error("Tool inputs changed during bake");view.free();quit(1);return
	var file:=FileAccess.open(Bake.RECEIPT,FileAccess.WRITE)
	if file==null:view.free();quit(1);return
	file.store_string(JSON.stringify({"schema":1,"sources":state,"outputs":outputs,"triangles":triangles},"  ")+"\n");file.close()
	view.free();print("TOOL_DROPS baked current held geometry and materials: ",triangles);quit()
