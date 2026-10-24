# SPDX-License-Identifier: 0BSD
extends SceneTree
const Icons=preload("res://addons/player_runtime/item_icons.gd")
var checks:=0
var failures:=0
var output:="res://reports/current_item_icons"
var previous:=""
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func render_nodes(node:Node)->int:
	var count:=int(node is SubViewport or node is Camera3D)
	for child in node.get_children():count+=render_nodes(child)
	return count
func capture(name:String)->void:
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--icon-evidence="):output=arg.trim_prefix("--icon-evidence=")
		if arg.begins_with("--icon-before="):previous=arg.trim_prefix("--icon-before=")
	DirAccess.make_dir_recursive_absolute(output)
	var background:=ColorRect.new();background.color=Color("182823");background.size=Vector2(1920,1080);background.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(background)
	var hud=preload("res://addons/player_runtime/player_hud.gd").new();hud.gameplay_construction=true;hud.resource_gains_allowed=func():return false
	var prepared:bool=hud.prepare();root.add_child(hud);await process_frame
	check(prepared and hud.inventory!=null,"actual inventory/toolbelt UI prepares")
	if not prepared or hud.inventory==null:hud.free();background.free();quit(1);return
	for id:int in [501,501,1,2]:hud.inventory.grant(id,1,hud.inventory.snapshot().revision)
	hud.refresh()
	check(hud.belt[0].item_texture==Icons.texture(1) and hud.belt[1].item_texture==Icons.texture(2) and hud.belt[9].item_texture==Icons.texture(501),"toolbelt uses refreshed pickaxe, hatchet and vehicle images")
	check(hud.slots[10].item_texture==Icons.texture(501) and hud.slots[11].item_texture==Icons.texture(1) and hud.slots[12].item_texture==Icons.texture(2),"backpack uses the same cached item images")
	check(Icons.texture(501) is AtlasTexture and Icons.texture(501).atlas==Icons.texture(1).atlas and Icons.texture(501)==Icons.texture(501),"vehicle and tools share one static cached atlas")
	var populated:=true
	for id:int in [1,2,501]:
		var image:Image=Icons.texture(id).get_image()
		if image.get_size()!=Vector2i(128,128) or image.get_used_rect().size==Vector2i.ZERO or image.get_pixel(0,0).a!=0:populated=false
	check(populated,"current model thumbnails are nonempty transparent 128px images")
	if not previous.is_empty():
		var before:=Image.new();var loaded:bool=before.load_png_from_buffer(FileAccess.get_file_as_bytes(previous))==OK
		var changed:Array=[]
		if loaded:
			var after:Image=Icons.atlas.get_image()
			for index in Icons.KEYS.size():
				var rect:=Rect2i((index%8)*128,(index/8)*128,128,128)
				if before.get_region(rect).get_data()!=after.get_region(rect).get_data():changed.append(Icons.KEYS[index])
		check(loaded and changed==["1","2","501"],"only pickaxe, hatchet and vehicle atlas tiles change: "+str(changed))
	check(render_nodes(root)==0,"inventory and toolbelt create no 3D cameras or live render viewports")
	await capture("toolbelt")
	hud.set_open(true);await capture("inventory")
	hud.free();background.free();await process_frame
	print("CURRENT_ITEM_ICONS checks=",checks," failures=",failures);quit(1 if failures else 0)
