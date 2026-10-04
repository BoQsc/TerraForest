# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Presentation=preload("res://addons/presentation/fullscreen_policy.gd")
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+30000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	check(not game.loading_active and game.terrain.world_ready,"actual main scene completes gameplay startup")
	if not game.loading_active:
		game.fly=true;game._clear_motion()
		check(game.construction_inventory.gameplay and game.player_hud.gameplay_construction and game.terrain.require_published_shutdown,"launcher mode wires construction, HUD and mining shutdown policy")
		check(game.player_hud.inventory.can_afford(PackedInt64Array([101,64,102,64,103,64,104,64]),game.player_hud.inventory.snapshot().revision).ok,"actual scene receives starter supplies")
		var center:=Vector3(800,30,1310)
		check(game.terrain.edit(Codec.brush(center,center,2,0,false,3),center-Vector3.ONE*8,center+Vector3.ONE*8),"main scene admits gameplay excavation")
		deadline=Time.get_ticks_msec()+15000
		while game.terrain.pending_edit and Time.get_ticks_msec()<deadline: await process_frame
		check(not game.terrain.pending_edit and not game.mining_rewards.failed,"streamed main-scene excavation publishes with reward callback")
		var pending: PackedInt64Array=game.player_hud.reward_inbox.get_pending()
		check(not pending.is_empty(),"main-scene excavation reaches pending inventory")
		game.player_hud.set_open(true)
		if not pending.is_empty():
			game.player_hud.pending_amount.value=2
			game.player_hud.claim_button.pressed.emit()
			var item: int=pending[0]
			var recipe:=0 if item==201 else (2 if item==202 else 3)
			game.player_hud.recipe_choice.select(recipe)
			game.player_hud.craft_button.pressed.emit()
			check(game.player_hud.message.text.begins_with("Crafted supplies"),"main-scene claim and crafting controls complete the resource conversion")
		check(game.player_hud.inventory_open and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"inventory opens with usable pointer in main scene")
		for frame in range(6): await RenderingServer.frame_post_draw
		check(Presentation.measurement(root).fair_graphical_sample and Engine.max_fps==60,"main scene uses fullscreen 1920x1080 and 60 FPS cap")
		DirAccess.make_dir_recursive_absolute("res://docs/evidence/gameplay_scene")
		root.get_texture().get_image().save_png("res://docs/evidence/gameplay_scene/inventory.png")
	game.shutdown_requested=true
	await game.terrain.shutdown_after_edits()
	game.free()
	for frame in range(2): await process_frame
	print("GAMEPLAY_SCENE ",JSON.stringify({"checks":checks,"failures":failures,"scope":"main scene startup, streamed edit and UI integration; not sustained FPS qualification"}))
	quit(1 if failures else 0)
