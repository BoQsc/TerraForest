# SPDX-License-Identifier: 0BSD
extends SceneTree
const Recipes=preload("res://reviews/building_expansion/recipes.gd")
func _initialize()->void:
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld")
	var manifest:={"revision":"E2","license":"CC0-1.0","source":"Original TerraForest buildings and reviews/building_expansion/recipes.gd","status":"unreviewed","assets":[]}
	manifest["recipe_sha256"]=FileAccess.get_sha256("res://reviews/building_expansion/recipes.gd")
	manifest["material_manifest_sha256"]=FileAccess.get_sha256("res://addons/structures/textures/expansion_v2/provenance.json")
	for index in Recipes.IDS.size():
		var asset:=Recipes.build(blocks,index)
		if asset==null:blocks.free();quit(1);return
		if preload("res://tools/doorway_dimensions.gd").normalize(asset,blocks)<0:blocks.free();quit(1);return
		var path:String="res://addons/structures/prefabs/expansion_"+Recipes.IDS[index]+"_e2.tres"
		if ResourceSaver.save(asset,path)!=OK:blocks.free();quit(1);return
		manifest.assets.append({"id":Recipes.IDS[index],"path":path,"baseline_sha256":asset.get_meta("baseline_sha256"),"sha256":FileAccess.get_sha256(path),"cells":asset.get_cell_count()})
	FileAccess.open("res://reviews/building_expansion/provenance.json",FileAccess.WRITE).store_string(JSON.stringify(manifest,"  ")+"\n")
	blocks.free();print("BAKE_BUILDING_EXPANSION count=",Recipes.IDS.size()," failures=0");quit()
