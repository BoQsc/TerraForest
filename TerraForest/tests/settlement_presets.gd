# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,message: String) -> void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	root.gui_embed_subwindows=true
	var palette=preload("res://addons/structures/construction_palette.gd").new();root.add_child(palette)
	var catalog=preload("res://addons/structures/furniture_catalog.gd")
	var assets: Array[Resource]=[catalog.enclosed_cottage(),catalog.furnished_tower()]
	palette.configure(assets);palette.synchronize(true,1,0,0,-1)
	check(not palette.frontage_button.disabled,"layout editor opens without first selecting a prefab")
	palette.frontage_button.pressed.emit();palette.frontage_presets[1].pressed.emit()
	var requests: Array=[]
	palette.settlement_requested.connect(func(indices,lots,width,gap,seed,title,streets):requests.append([indices,lots,width,gap,seed,title,streets]))
	await process_frame;await process_frame
	check(palette.frontage_dialog.visible and palette.frontage_dialog.size.y<=1080,"preset dialog fits fullscreen height")
	check(palette.frontage_sources.select_mode==ItemList.SELECT_TOGGLE,"building selection needs no keyboard modifier")
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://reports/settlement_presets")
	root.get_texture().get_image().save_png("res://reports/settlement_presets/mixed.png")
	palette.frontage_dialog.confirmed.emit()
	check(requests.size()==1,"preset submits one settlement request")
	if requests.size()==1:
		var r: Array=requests[0];var selected: Array[Resource]=[]
		for i in r[0]:selected.append(assets[i])
		var result: Resource=ClassDB.instantiate("NativeBlockPrefab")
		check(result.compose_settlement(selected,r[1],r[2],r[3],r[4],r[6]),"actual UI request composes through native settlement path")
		check(result.get_cell_count()==6771 and result.get_model_attachments().size()==263,"preset matches verified mixed neighborhood blocks and attachments")
		check(r[5]=="Mixed neighborhood","layout name comes from visible dialog")
	palette.frontage_button.pressed.emit();palette.frontage_sources.deselect_all();palette.frontage_dialog.confirmed.emit()
	check(requests.size()==1 and palette.frontage_dialog.visible and not palette.frontage_status.text.is_empty(),"empty selection stays open with feedback and cannot submit generation")
	palette.frontage_presets[0].pressed.emit();palette.frontage_dialog.confirmed.emit()
	check(requests.size()==2 and requests[1][0].size()==1 and requests[1][1]==1,"cottage preset replaces mixed selection and restores small layout")
	palette.free();print("SETTLEMENT_PRESETS failures=",failures);quit(1 if failures else 0)
