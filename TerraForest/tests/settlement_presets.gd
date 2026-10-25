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
		var expected_blocks: int=5*assets[0].get_cell_count()+3*assets[1].get_cell_count()
		var expected_models: int=5*assets[0].get_model_attachments().size()+3*assets[1].get_model_attachments().size()
		check(r[0]==PackedInt32Array([0,1]) and r[1]==2 and r[2]==8 and r[3]==3 and r[4]==1703 and r[6]==2,"mixed preset retains both sources and its exact seeded layout settings")
		print("MIXED_PRESET blocks=",result.get_cell_count()," models=",result.get_model_attachments().size()," expected_blocks=",expected_blocks," expected_models=",expected_models)
		check(result.get_cell_count()==expected_blocks and result.get_model_attachments().size()==expected_models,"seeded preset composes exactly five current cottages and three current towers")
		check(r[5]=="Mixed neighborhood","layout name comes from visible dialog")
	palette.frontage_button.pressed.emit();palette.frontage_sources.deselect_all();palette.frontage_dialog.confirmed.emit()
	check(requests.size()==1 and palette.frontage_dialog.visible and not palette.frontage_status.text.is_empty(),"empty selection stays open with feedback and cannot submit generation")
	palette.frontage_presets[0].pressed.emit();palette.frontage_dialog.confirmed.emit()
	check(requests.size()==2 and requests[1][0].size()==1 and requests[1][1]==1,"cottage preset replaces mixed selection and restores small layout")
	palette.frontage_button.pressed.emit();palette.frontage_sources.deselect_all();palette.frontage_sources.select(1)
	palette.frontage_streets.value=1;palette.frontage_lots.value=32
	palette.frontage_dialog.confirmed.emit()
	check(requests.size()==2 and palette.frontage_dialog.visible and "4096" in palette.frontage_status.text,"oversized attachment layout stays in dialog without dispatching generation")
	palette.free();print("SETTLEMENT_PRESETS failures=",failures);quit(1 if failures else 0)
