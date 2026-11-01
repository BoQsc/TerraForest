# SPDX-License-Identifier: 0BSD
extends SceneTree
const ROOT="res://addons/structures/textures/expansion_v2/"
var failures:=0
func _initialize()->void:run.call_deferred()
func run()->void:
	var receipt:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(ROOT+"provenance.json"))
	var folder:="res://reports/building_expansion/materials_"+str(Time.get_unix_time_from_system()).replace(".","_")
	DirAccess.make_dir_recursive_absolute(folder)
	var results:=[]
	for asset:Dictionary in receipt.assets:
		var pixels:=Image.new()
		var ok:bool=pixels.load_png_from_buffer(FileAccess.get_file_as_bytes(asset["512"].path))==OK and pixels.get_width()==512 and pixels.get_height()==512 and FileAccess.get_sha256(asset["512"].path)==asset["512"].sha256
		if not ok:failures+=1;continue
		# Technical repeat inspection sheet; source pixels are never modified.
		var tiled:=Image.create(1536,1536,false,Image.FORMAT_RGB8)
		for y in 3:
			for x in 3:tiled.blit_rect(pixels,Rect2i(0,0,512,512),Vector2i(x,y)*512)
		tiled.save_png(folder.path_join(asset.name+"_repeat.png"))
		var horizontal:=0.;var vertical:=0.;var mean:=Color(0,0,0)
		for y in 512:
			var a:=pixels.get_pixel(0,y);var b:=pixels.get_pixel(511,y);horizontal+=(absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b))/3
			var c:=pixels.get_pixel(y,0);var d:=pixels.get_pixel(y,511);vertical+=(absf(c.r-d.r)+absf(c.g-d.g)+absf(c.b-d.b))/3
			for x in 512:mean+=pixels.get_pixel(x,y)
		mean/=512*512
		results.append({"name":asset.name,"horizontal_edge_mean_difference":horizontal/512,"vertical_edge_mean_difference":vertical/512,"mean_rgb":[mean.r,mean.g,mean.b],"repeat_image":folder.path_join(asset.name+"_repeat.png")})
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"assets":results,"source":receipt,"failures":failures,"note":"Edge differences are diagnostic, not an automatic visual acceptance threshold."},"  "))
	FileAccess.open("res://reports/building_expansion/latest_materials.json",FileAccess.WRITE).store_string(JSON.stringify({"folder":folder}))
	print("BUILDING_MATERIALS checks=8 failures=",failures," folder=",folder);quit(1 if failures else 0)
