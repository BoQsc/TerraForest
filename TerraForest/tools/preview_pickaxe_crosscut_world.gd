# SPDX-License-Identifier: 0BSD
extends "res://tools/playtest_pickaxe_crosscut.gd"
const OUTPUT="res://reports/pickaxe_crosscut/world_visual"
func run()->void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	root.position=Vector2i(-32000,-32000)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	await super.run()
	var game=current_scene
	if not is_instance_valid(game):return
	var view=game.tool_view.human
	game.tool_view.set_process(false);view.set_process(false)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	paused=true
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var records:Array=[]
	for entry in [["current_hold",false,0.0],["arc_hold",true,0.0],["arc_load",true,28.0/60],["arc_approach",true,38.0/60],["arc_contact",true,.7],["arc_follow",true,50.0/60],["arc_return",true,69.0/60]]:
		view.set_candidate(entry[1])
		var clip:String=("FP_Pickaxe_Crosscut_" if entry[1] else "FP_Pickaxe_Fresh_")+("Idle" if entry[2]==0 else "Swing")
		view.animation_player.play(view.clips[clip],0);view.animation_player.seek(entry[2],true);view.animation_player.pause();view.animation_player.advance(0)
		for control in root.get_children():
			if control is ReviewControls:control.refresh()
		await process_frame;RenderingServer.force_draw(false);RenderingServer.force_draw(false)
		var path:String=OUTPUT+"/"+entry[0]+".png"
		var shot:Image=root.get_texture().get_image();shot.save_png(path)
		records.append({"file":path,"clip":clip,"time":entry[2],"image_size":[shot.get_width(),shot.get_height()]})
	var report:={"temporary":game.temporary_world,"seed":game.terrain.backend.world_seed,"camera":str(game.camera.global_transform),"fov":game.camera.fov,"viewport":[root.size.x,root.size.y],"captures":records}
	FileAccess.open(OUTPUT+"/manifest.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	paused=false;game.shutdown_requested=true
	await game.terrain.shutdown_after_edits()
	game.free();await process_frame;await process_frame
	print("PICKAXE_WORLD_VISUAL ",JSON.stringify(report));quit()
