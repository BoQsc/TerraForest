# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var background:=ColorRect.new();background.color=Color("182823");background.size=Vector2(1920,1080);background.mouse_filter=Control.MOUSE_FILTER_IGNORE;root.add_child(background)
	var title:=Label.new();title.position=Vector2(180,100);title.text="BAKED ITEM ICONS / shared atlas / durability and hover";title.add_theme_font_size_override("font_size",28);root.add_child(title)
	var icons=preload("res://addons/player_runtime/item_icons.gd")
	var structures=preload("res://addons/structures/structures_world.gd").new();root.add_child(structures)
	check(structures.prepare(),"production structure catalog prepared")
	for catalog in [preload("res://addons/structures/window_catalog.gd"),preload("res://addons/structures/door_catalog.gd"),preload("res://addons/structures/guardrail_catalog.gd"),preload("res://addons/structures/fence_catalog.gd")]:
		var entry: Dictionary=catalog.register(structures)
		check(not entry.is_empty() and icons.texture(entry.get("title",""))!=null,"production object title resolves baked icon")
	structures.free()
	var hud=preload("res://addons/player_runtime/player_hud.gd")
	var first: Button
	var occupied:=true
	for i in icons.KEYS.size():
		var key: String=icons.KEYS[i];var id:=key.to_int()
		var button=preload("res://addons/player_runtime/inventory_slot.gd").new();button.position=Vector2(180+(i%8)*190,190+(i/8)*160);button.size=Vector2(170,125);root.add_child(button)
		var name: String=hud.CATALOG.get(id,hud.MATERIALS.get(id,hud.RESOURCES.get(id,key)))
		button.present({"item":key,"count":1,"durability":40 if i==0 else 200,"max_durability":200 if id in [1,2,3,4] else 0},name)
		button.set_appearance(false,i==0)
		if i==0:first=button
		var image: Image=icons.texture(key).get_image();occupied=occupied and image.get_used_rect().size!=Vector2i.ZERO
	check(occupied,"all baked tiles contain visible pixels")
	check(icons.texture(99999)==null,"unknown identity has safe missing-icon fallback")
	var image: Image=icons.atlas.get_image()
	check(image.get_size()==Vector2i(1024,ceili(icons.KEYS.size()/8.0)*128) and image.get_pixel(0,0).a==0,"transparent atlas fits catalog rows")
	var point:=first.get_global_rect().get_center();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE;Input.warp_mouse(point)
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;Input.parse_input_event(motion)
	await create_timer(1.2).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://reports/item_icons")
	root.get_texture().get_image().save_png("res://reports/item_icons/catalog_tooltip.png")
	print("ITEM_ICONS failures=",failures);quit(1 if failures else 0)
