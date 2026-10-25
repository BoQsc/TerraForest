extends SceneTree

var checks := 0
var failures := 0
var game: Node3D
var reference := "res://reviews/modular_buildings/baked/shop_b.tres"

func _initialize() -> void:run.call_deferred()

func check(accepted: bool, label: String) -> void:
	checks+=1
	if not accepted:failures+=1
	print("PASS " if accepted else "FAIL ",label)

func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--approved-reference="):reference=argument.trim_prefix("--approved-reference=")
	var workshop: Script=load("res://addons/structures/workshop_catalog.gd")
	var approved: Resource=workshop.hipped_shop()
	var reviewed: Resource=load(reference)
	check(approved!=null and reviewed!=null,"approved shop and exact user-reviewed reference load")
	if approved==null or reviewed==null:quit(1);return
	check(approved.get_records()==reviewed.get_records() and approved.get_model_attachments()==reviewed.get_model_attachments(),"approved B1 geometry and attachments copied exactly, not redesigned")
	check(approved.get_meta("approved_as_addition",false) and approved.get_meta("approved_revision","")=="B1 R1" and not approved.get_meta("review_only",false),"production prefab records addition-only approval")
	var original: Resource=workshop.legacy_village_shop()
	check(original.resource_name=="Village general store" and original.get_records()!=approved.get_records(),"original shop remains a distinct unchanged recipe")
	check(original.get_model_attachments()==approved.get_model_attachments(),"approved shop retains original doors, windows, furniture and storage")
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"actual temporary gameplay world finishes loading")
	if not game.loading_active:
		game.set_physics_process(false);game.app_focused=true;game.session_menu.set_open(false)
		var approved_index:=-1
		var approved_count:=0
		var rejected_count:=0
		for index in game.structure_prefabs.size():
			var asset: Resource=game.structure_prefabs[index]
			if asset.resource_path==approved.resource_path:approved_index=index;approved_count+=1
			if asset.resource_name.contains("Cottage A") or asset.resource_path.begins_with("res://reviews/"):rejected_count+=1
		check(approved_count==1 and approved_index==game.structure_prefabs.size()-1,"B1 appended exactly once without shifting existing prefab indices")
		check(rejected_count==0,"no rejected cottage or review-only prefab in gameplay palette")
		var furniture: Script=load("res://addons/structures/furniture_catalog.gd")
		check(game.structure_prefabs[0].resource_path=="res://addons/structures/prefabs/brick_cottage.tres" and game.structure_prefabs[6].get_records()==furniture.enclosed_cottage().get_records(),"legacy cottage retained and approved enclosed cottage keeps its palette index")
		if approved_index>=0:
			var palette: Node=game.construction_palette
			check(palette.prefab.get_item_text(approved_index+1)==approved.resource_name,"construction UI names the new shop separately")
			check(game._set_player_tool_mode(true,false,-1),"normal developer building tool activates")
			palette.prefab.select(approved_index+1);palette.prefab.item_selected.emit(approved_index+1)
			check(game.structure_prefab_index==approved_index,"normal UI selection selects the approved shop")
	game.shutdown_requested=true
	await game.terrain.shutdown_after_edits()
	game.free();await process_frame
	print("APPROVED_SHOP_ADDITION checks=",checks," failures=",failures)
	quit(1 if failures else 0)
