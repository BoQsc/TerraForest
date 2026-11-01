# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"

var game:Node
var expected:Dictionary={}

func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	node_added.connect(func(node:Node):
		if node.scene_file_path=="res://demo/world.tscn":ProjectSettings.set_setting("terraforest/offscreen_session",true))
	super._initialize()

func run()->void:
	var restore:bool="--restore-progression" in OS.get_cmdline_user_args()
	expected=FileAccess.open(folder.path_join("expected.bin"),FileAccess.READ).get_var() if restore else JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("world.json")))
	if not check(str(expected.slot).begins_with("Exploration_"),"only the owned exploration fixture is modified"):await finish();return
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed;await wait_for(browser_catalog_ready)
	var browser=current_scene;var selected:=-1
	for index in browser.worlds.item_count:
		if browser.worlds.get_item_metadata(index)==expected.slot:selected=index;break
	if not check(selected>=0,"normal selector lists the generated fixture"):await finish();return
	browser.worlds.select(selected);browser.launch_selected(false)
	if not check(await wait_for(game_ready,100),"ordinary saved-world loading reaches gameplay"):await finish();return
	game=current_scene;game.background_fps=60;game.app_focused=true;game.set_physics_process(false);game._clear_motion()
	game.zombies.update(0,game.player.global_position,false)
	var hud:Node=game.player_hud
	if restore:
		check(hud.progression.capture_storage_snapshot()==expected.progression,"fresh process restores exact earned XP and chosen skill")
		check(hud.inventory.capture_storage_snapshot()==expected.inventory,"mining rewards, crafting costs and tool wear restore together")
		check(hud.skill_damage(1,30)==expected.damage,"saved skill changes the actual gameplay damage adapter")
		hud.set_open(true);hud.show_side("Skills");await photograph("skills-restored")
		await finish();return
	check(game.persistence._providers.has("player_progression"),"ordinary compound save owns progression")
	var before:Dictionary=hud.progression.snapshot()
	print("PROGRESSION_BEFORE ",JSON.stringify(before))
	check(before.xp>=0 and before.skills[1]==0,"owned test character is ready to earn its first mining skill")
	var place:Dictionary=game.generated_region.store.get_plan().places[0]
	var anchor:Vector3=place.position+Vector3(30,0,30)
	game.teleport(anchor)
	if not check(await wait_for(game_ready,90),"normal terrain streaming reaches outdoor mining area"):await finish();return
	game.set_physics_process(false);game.app_focused=true;game.zombies.update(0,game.player.global_position,false)
	hud.equip_item(1)
	var published:=0
	for index in 8:
		if hud.progression.snapshot().points>0:break
		var horizontal:=anchor+Vector3((index%8)*1.5,0,(index/8)*1.5)
		var start:=Vector3(horizontal.x,game.player.position.y+18,horizontal.z)
		var end:=start-Vector3.UP*65
		if not check(await wait_for(func():return not game._terrain_pick(start,end).is_empty(),12),"native density ray locates visible generated ground"):break
		var surface:Dictionary=game._terrain_pick(start,end)
		game.camera.global_position=surface.position+Vector3(.2,1.8,.2);game.camera.look_at(surface.position)
		var cell:=Vector3i((surface.position-surface.normal*.05).floor())
		var target:Dictionary={"kind":"terrain","key":game.world_attack.block_key(cell).replace("block:","terrain:"),"health":30,"material":"stone","name":"Terrain","position":surface.position,"normal":surface.normal}
		var xp:int=hud.progression.snapshot().xp
		if not check(game.world_attack.apply_target(target),"real pickaxe contact adapter admits excavation"):break
		if not check(await wait_for(func():return not game.terrain.pending_edit,15),"native excavation publishes"):break
		if hud.progression.snapshot().xp>xp:published+=1
		hud.set_open(true);hud.craft_recipe(0);hud.set_open(false)
	hud.equip_item(2)
	var felled:=0
	var candidates:Array=game.vegetation.renderer.roots.keys()
	for identity:int in candidates:
		if hud.progression.snapshot().points>0 or felled>=20:break
		var owner:int=(identity-1)/(game.ecosystem.GRID*game.ecosystem.GRID)
		var key:=Vector2i(owner%32,owner/32)
		if not game.ecosystem._samples.has(key) or not game.ecosystem._samples[key].active.has(identity) or game.ecosystem._pending_cells.has(key) or game.ecosystem._reconcile.has(key) or game.ecosystem._resample.has(key):continue
		var tree:Dictionary={"kind":"tree","id":identity,"key":"tree:%d"%identity,"health":90,"material":"wood","name":"Tree"}
		var prior:int=hud.progression.snapshot().xp
		for strike in 3:check(game.world_attack.apply_target(tree),"real generated-tree harvest pays experience after accepted damage")
		check(hud.progression.snapshot().xp>prior and game.ecosystem.harvest_state.contains(identity),"felling pays its finishing bonus and persists removal")
		prior=hud.progression.snapshot().xp
		check(not game.world_attack.apply_target(tree) and hud.progression.snapshot().xp==prior,"stale felled-tree target cannot farm experience")
		felled+=1
	print("PROGRESSION_EARNED ",JSON.stringify(hud.progression.snapshot()))
	check(published>0 and hud.progression.snapshot().xp>before.xp,"real published excavations and paid crafting grant experience")
	check(hud.progression.snapshot().points>0,"ordinary doing/crafting earns a spendable level without test XP grants")
	hud.set_open(true);hud.show_side("Skills");hud.skills_panel.buttons[0].pressed.emit()
	check(hud.progression.snapshot().skills[1]==1 and hud.skill_damage(1,30)==32,"actual Skills button spends earned point and improves mining")
	await photograph("skills-earned")
	expected.progression=hud.progression.capture_storage_snapshot();expected.inventory=hud.inventory.capture_storage_snapshot();expected.damage=hud.skill_damage(1,30)
	FileAccess.open(folder.path_join("expected.bin"),FileAccess.WRITE).store_var(expected)
	await finish()

func finish()->void:
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED and preload("res://addons/world_runtime/mouse_ownership.gd").captures==0,"test does not capture the desktop pointer")
	if game_ready():
		current_scene.shutdown_requested=true;check(await current_scene.terrain.shutdown_after_edits(),"owned test world saves durably")
	if is_instance_valid(current_scene):current_scene.free()
	print("PLAYER_PROGRESSION_WORLD checks=",checks," failures=",failures)
	quit(1 if failures else 0)
