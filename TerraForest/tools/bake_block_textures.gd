# SPDX-License-Identifier: 0BSD
extends SceneTree
const ROOT="res://addons/structures/textures/"
func _initialize()->void:
	var inputs:Dictionary={}
	var outputs:Dictionary={}
	var groups:Dictionary={}
	for group:String in ["original","terraforest","expansion_v2"]:
		var names:Array=["brick_albedo.png","wood_albedo.png","concrete_albedo.png","metal_albedo.png"] if group!="expansion_v2" else ["aged_brick.trtex","weathered_plaster.trtex","coursed_limestone.trtex","weathered_timber.trtex","slate.trtex","patinated_zinc.trtex","aged_terracotta.trtex","soot_stone_trim.trtex"]
		groups[group]=names
		for name:String in names:inputs[group+"/"+name]=FileAccess.get_sha256(ROOT+group+"/"+name)
	var manifest_path:=ROOT+"arrays/bake.json"
	var previous=JSON.parse_string(FileAccess.get_file_as_string(manifest_path)) if FileAccess.file_exists(manifest_path) else null
	var current:bool=previous is Dictionary and previous.get("inputs",{})==inputs and previous.get("version",0)==1
	if current:
		for group:String in groups:
			if previous.get("outputs",{}).get(group,"")!=FileAccess.get_sha256(ROOT+"arrays/"+group+".res"):current=false
	if current:print("BLOCK_TEXTURE_BAKE current");quit();return
	DirAccess.make_dir_recursive_absolute(ROOT+"arrays")
	for group:String in groups:
		var images:Array[Image]=[]
		for name:String in groups[group]:
			var image:=Image.new()
			if image.load_png_from_buffer(FileAccess.get_file_as_bytes(ROOT+group+"/"+name))!=OK:quit(1);return
			image.convert(Image.FORMAT_RGB8)
			if image.generate_mipmaps()!=OK:quit(1);return
			images.append(image)
		var texture:=Resource.new()
		texture.set_meta("images",images)
		var path:=ROOT+"arrays/"+group+".res"
		if ResourceSaver.save(texture,path,ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
		var restored:Resource=load(path)
		for index in images.size():
			if restored.get_meta("images")[index].get_data()!=images[index].get_data():quit(1);return
		outputs[group]=FileAccess.get_sha256(path)
	FileAccess.open(manifest_path,FileAccess.WRITE).store_string(JSON.stringify({"version":1,"inputs":inputs,"outputs":outputs,"provenance":"Lossless texture-array/mipmap bake of existing project textures; inherited source notices and provenance unchanged."},"\t"))
	print("BLOCK_TEXTURE_BAKE verified");quit()
