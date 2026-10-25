# SPDX-License-Identifier: 0BSD
extends "res://tests/water_bucket_roundtrip.gd"
var visual_checks:=0
func verify(ok:bool,label:String)->void:
	visual_checks+=1;check(ok,label)
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED);root.position=Vector2i(-32000,-32000)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
	verify(game.has_meta("water_bucket_review_ready") and game.temporary_world,"temporary water-review world is ready")
	if failures:await finish();return
	game.set_physics_process(false);game._clear_motion();game.zombies.clear()
	ProjectSettings.set_setting("terraforest/offscreen_session",false)
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	var view=game.tool_view.human;view.set_process(false)
	verify(view.active_clip=="FP_Bucket_Idle" and view.current==401 and not view.bucket_water.visible,"ordinary empty-slot equipment selects the Blender bucket")
	var total:int=game.lakes.statistics().water_ml
	click(MOUSE_BUTTON_LEFT)
	verify(await wait_publication() and held_ml()==1000000 and game.lakes.statistics().water_ml==total-1000000,"real left click transfers one complete water unit")
	verify(view.bucket_water.visible and view.bucket_fill==1 and view.active_clip=="FP_Bucket_Scoop","confirmed filling updates water metadata and starts the scoop clip")
	advance_pose(.45);await capture_visual("filled")
	advance_pose(1)
	verify(view.active_clip=="FP_Bucket_Idle","scoop finishes at the carry pose")
	var start:Vector3=game.player.global_position+Vector3(0,0,10)
	var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start+Vector3.UP*30,start-Vector3.UP*30,1))
	verify(not hit.is_empty(),"nearby native ground supplies a pour target")
	if hit.is_empty():await finish();return
	aim(hit.position);click(MOUSE_BUTTON_RIGHT)
	verify(await wait_publication() and held_ml()==0,"real right click pours the complete water unit")
	verify(not view.bucket_water.visible and view.bucket_fill==0 and view.active_clip=="FP_Bucket_Pour","confirmed emptying clears the surface and starts the pour clip")
	advance_pose(.5);await capture_visual("empty_pour")
	advance_pose(1)
	click(MOUSE_BUTTON_LEFT)
	verify(await wait_publication() and held_ml()==1000000 and view.bucket_water.visible,"one click recovers the pour and restores the filled bucket visual")
	game.player_hud.equip_item(1)
	verify(view.active_clip=="FP_Pickaxe_Fresh_Idle" and not view.bucket_water.visible,"normal inventory switch restores the accepted pickaxe without bucket water")
	await finish()
func advance_pose(seconds:float)->void:
	# Advance the normal blend over successive frames; one large advance samples
	# the old crossfade endpoint on its first render and is not a usable pose capture.
	for frame in roundi(seconds*60):game.tool_view.human._process(1.0/60.0)
func capture_visual(label:String)->void:
	await process_frame;await process_frame;RenderingServer.force_draw(false);RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("res://reports/water_bucket_visuals/world_"+label+".png")
func finish()->void:
	game.shutdown_requested=true
	verify(await game.terrain.shutdown_after_edits(),"temporary world shuts down without saving player data")
	game.free();await process_frame;await process_frame
	FileAccess.open("res://reports/water_bucket_visuals/world.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":visual_checks,"failures":failures,"scope":"Real world, native water and inventory, actual mouse collect/pour/recollect, visible fill and authored motion. No change to transfer permissions or water units."},"  "))
	print("WATER_BUCKET_VISUALS_WORLD checks=",visual_checks," failures=",failures);quit(1 if failures else 0)
