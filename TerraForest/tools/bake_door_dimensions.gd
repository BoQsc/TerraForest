# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
	var blocks:Node=ClassDB.instantiate("NativeBlockWorld")
	var receipts:=[]
	var folder:="res://addons/structures/prefabs"
	for name:String in DirAccess.get_files_at(folder):
		if not name.ends_with(".tres"):continue
		var path:=folder.path_join(name)
		var asset:Resource=load(path)
		if not asset.has_method("get_model_attachments"):continue
		var before:=FileAccess.get_sha256(path)
		var count:int=preload("res://tools/doorway_dimensions.gd").normalize(asset,blocks)
		if count<0:blocks.free();quit(1);return
		if count==0:continue
		if ResourceSaver.save(asset,path)!=OK:blocks.free();quit(1);return
		receipts.append({"path":path,"doors":count,"before_sha256":before,"after_sha256":FileAccess.get_sha256(path)})
	DirAccess.make_dir_recursive_absolute("res://reports/door_dimensions")
	FileAccess.open("res://reports/door_dimensions/bake.json",FileAccess.WRITE).store_string(JSON.stringify(receipts,"  "))
	blocks.free();print("DOOR_DIMENSIONS_BAKE assets=",receipts.size()," failures=0");quit()
