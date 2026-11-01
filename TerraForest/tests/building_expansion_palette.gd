# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	var palette:=preload("res://addons/structures/construction_palette.gd").new();root.add_child(palette)
	var events:=[];palette.selection_requested.connect(func(field:String,value:int):events.append([field,value]))
	palette.synchronize(true,19,2,17,-1,true,4)
	check(palette.shape.get_selected_id()==18 and palette.rotation_choice.selected==17 and palette.appearance.selected==5,"shape, mount and appearance synchronize independently")
	palette.search.text="shallow";palette._filter_shapes()
	check(palette.shape.item_count==12 and palette.shape.get_selected_id()==18,"search uses shape names and preserves native identity")
	var high:=palette.shape.get_item_index(19);palette.shape.select(high);palette.shape.item_selected.emit(high)
	check(events[-1]==["shape",19],"filtered mouse selection emits original shape ID")
	palette.search.text="31";palette._filter_shapes()
	check(palette.shape.item_count==1 and palette.shape.get_item_id(0)==30,"exact numeric search finds coping corner")
	palette.search.text="";palette.family.select(4);palette._filter_shapes()
	check(palette.shape.item_count==4,"trim family excludes roof shapes")
	palette.family.select(0);palette._filter_shapes();palette.synchronize(true,19,2,17,-1,true,4)
	check(palette.orientation_preview.texture!=null and palette.orientation_preview.texture.region==Rect2(320,128,64,64),"baked thumbnail follows selected mounting direction")
	var assets:Array[Resource]=[load("res://addons/structures/prefabs/civic_review_school_s2.tres")];palette.configure(assets)
	palette.synchronize(true,19,2,1,0,true,4)
	check(palette.shape.disabled and palette.appearance.disabled and palette.rotation_choice.item_count==4,"prefab mode retains prefab selection and locks cell styling")
	palette.synchronize(true,19,2,17,-1,true,4)
	for child in palette.editor_controls:child.hide()
	palette.panel.position=Vector2(40,40)
	if DisplayServer.get_name()!="headless":
		for frame in 3:await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://reports/building_expansion/palette")
		root.get_texture().get_image().save_png("res://reports/building_expansion/palette/palette.png")
	check(palette.panel.size.y<850,"core construction controls fit a 1080p viewport")
	palette.free();print("BUILDING_EXPANSION_PALETTE checks=",checks," failures=",failures);quit(1 if failures else 0)
