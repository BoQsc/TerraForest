# SPDX-License-Identifier: 0BSD
extends SceneTree
const Presentation=preload("res://addons/presentation/fullscreen_policy.gd")
func _initialize() -> void:run.call_deferred()
func run() -> void:
    var game: Node=load("res://demo/world.tscn").instantiate();root.add_child(game)
    var deadline:=Time.get_ticks_msec()+60000
    while game.loading_active and Time.get_ticks_msec()<deadline:
        await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    var state: Dictionary=Presentation.measurement(root)
    var passed: bool=not game.loading_active and game.terrain.world_ready and game.terrain.latest_error.is_empty() and state.fair_graphical_sample and DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_ENABLED and not game.temporary_world and game.max_fps==60 and Engine.max_fps==60 and not game.terrain.backend.snapshot_terrain and not game.terrain.backend.region_terrain
    state["ready"]=not game.loading_active
    state["passed"]=passed
    state["requested_fps_cap"]=game.max_fps
    state["actual_fps_cap"]=Engine.max_fps
    state["vsync"]=DisplayServer.window_get_vsync_mode()
    state["slot"]=game.terrain.save_slot
    state["save_path"]=ProjectSettings.globalize_path(game.terrain.backend.save_path)
    state["scope"]="Automatic real-scene startup/presentation check only; no human playtest or 60 FPS performance qualification."
    var report:=FileAccess.open("res://reports/playtest_startup.json",FileAccess.WRITE);report.store_string(JSON.stringify(state,"  "));report.close()
    root.get_texture().get_image().save_png("res://reports/playtest_startup.png")
    print("PASS " if passed else "FAIL ","PLAYTEST_STARTUP ",JSON.stringify(state))
    game.shutdown_requested=true
    await game.terrain.shutdown_after_edits()
    quit(0 if passed else 1)
