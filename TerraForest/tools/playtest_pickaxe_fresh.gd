# SPDX-License-Identifier: 0BSD
extends SceneTree
## Temporary world for the accepted default, using ordinary runtime routing.

func _initialize() -> void:
	run.call_deferred()

func verify() -> void:
	var view = preload("res://addons/player_runtime/tool_view.gd").new()
	root.add_child(view)
	view.equip(1)
	view.human.set_process(false)
	var contacts: Array = []
	var finishes: Array = []
	view.attack_contact.connect(func(identity: int): contacts.append([identity, view.contact_ready(identity), view.human.animation_player.current_animation_position]))
	view.attack_finished.connect(func(identity: int, cancelled: bool): finishes.append([identity, cancelled]))
	var profile: Dictionary = view.attack_profile()
	var ok: bool = profile.clip == "FP_Pickaxe_Fresh_Swing" and is_equal_approx(profile.contact, 50.0 / 60.0)
	ok = view.begin_attack(71) and ok
	for frame in 125: view.human._process(1.0 / 60.0)
	ok = ok and contacts.size() == 1 and contacts[0][0] == 71 and contacts[0][1] and is_equal_approx(contacts[0][2], 50.0 / 60.0)
	ok = ok and finishes == [[71, false]] and view.human.active_clip == "FP_Pickaxe_Fresh_Idle"
	view.equip(2)
	ok = ok and view.attack_profile().clip == "FP_Axe_Swing"
	print("PICKAXE_FRESH_PLAYTEST_CHECK ", JSON.stringify({"ok": ok, "profile": profile, "contacts": contacts, "finishes": finishes}))
	view.free()
	quit(0 if ok else 1)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if "--verify" in args:
		verify()
		return
	# Force ephemeral storage even if this script is started without flags.
	if "--temporary" not in args: args.append("--temporary")
	ProjectSettings.set_setting("terraforest/session_arguments", args)
	var game = load("res://demo/world.tscn").instantiate()
	game.temporary_world = true
	root.add_child(game)
	current_scene = game
	var deadline := Time.get_ticks_msec() + 90000
	while (game.loading_active or game.needs_floor_spawn) and Time.get_ticks_msec() < deadline:
		await process_frame
	if game.loading_active or game.needs_floor_spawn:
		push_error("Fixed-grip playtest could not finish loading")
		quit(2)
		return
	game.player_hud.equip_item(1)
	DisplayServer.window_set_title("TerraForest - fixed-grip pickaxe preview (temporary world)")
	var folder := "res://reports/pickaxe_fresh"
	for arg in args:
		if arg.begins_with("--playtest-evidence="): folder = arg.trim_prefix("--playtest-evidence=")
	DirAccess.make_dir_recursive_absolute(folder)
	var ready := {"temporary": game.temporary_world, "equipped": game.equipped_tool, "profile": game.tool_view.attack_profile(), "position": str(game.player.position)}
	FileAccess.open(folder + "/ready.json", FileAccess.WRITE).store_string(JSON.stringify(ready, "\t"))
	print("PICKAXE_FRESH_PLAYTEST_READY ", JSON.stringify(ready))
	if DisplayServer.get_name() != "headless":
		# Allow the normal equip blend to finish before recording the ready pose.
		await create_timer(0.25).timeout
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder + "/ready.png")
