# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
	var path:="";var output:=""
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--world-root="):path=argument.trim_prefix("--world-root=")
		if argument.begins_with("--inspection-output="):output=argument.trim_prefix("--inspection-output=")
	if path.is_empty() or output.is_empty():quit(1);return
	var verifier:RefCounted=ClassDB.instantiate("NativeGeneratedWorldVerifier")
	var result:Dictionary=verifier.inspect(path)
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:quit(1);return
	file.store_string(JSON.stringify(result,"  "));file.close()
	print("WORLD_INSPECTOR_NATIVE ok=",result.get("ok",false))
	quit(0 if result.get("ok",false) else 1)
