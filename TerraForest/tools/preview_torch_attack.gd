# SPDX-License-Identifier: 0BSD
extends "res://tools/preview_pickaxe_fresh.gd"
const OUTPUT="res://reports/torch_attack"
func setup(kind:String)->Dictionary:
	var data:=panel(kind);data.view.equip(6);data.view.torch_effects.set_process(false)
	data.view.animation_player.add_animation_library("attack_review",load("res://addons/characters/authoring/Human.torch_attack.res"))
	data.view.clips["FP_Torch_Swing"]="attack_review/FP_Torch_Swing"
	for child in data.viewport.get_children():
		if child is Label:child.queue_free()
	# Remove the pickaxe fixture; the candidate has no damage or target response.
	for child in data.camera.get_parent().get_children():
		if child is MeshInstance3D and not child.mesh is PlaneMesh:child.queue_free()
	return data
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUTPUT+"/frames")
	FileAccess.open(OUTPUT+"/.gdignore",FileAccess.WRITE).store_string("")
	var front:=setup("fresh");var side:=setup("side")
	front.viewport.size=Vector2i(960,540);side.viewport.size=Vector2i(640,540)
	side.camera.position=Vector3(1.55,1.65,-1.75);side.camera.fov=40;side.camera.look_at(Vector3(.10,1.43,-.30))
	var canvas:=SubViewport.new();canvas.size=Vector2i(1600,640);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var bg:=ColorRect.new();bg.size=canvas.size;bg.color=Color("1e272d");canvas.add_child(bg)
	label(canvas,"TORCH ATTACK / REVISION 02",Vector2(24,12),26,Color("edc798"))
	label(canvas,"First person",Vector2(690,19),20)
	label(canvas,"Body mechanics",Vector2(1010,19),20)
	var note:=label(canvas,"",Vector2(24,599),21)
	for entry in [[front,Vector2(0,52),Vector2(960,540)],[side,Vector2(960,52),Vector2(640,540)]]:
		var picture:=TextureRect.new();picture.texture=entry[0].viewport.get_texture();picture.position=entry[1];picture.size=entry[2];canvas.add_child(picture)
	var stills:=OS.get_cmdline_user_args().has("--stills")
	var frames:Array=[0,15,22,28,31,36,48] if stills else range(234)
	for frame:int in frames:
		var elapsed:=frame/30.0;var cursor:=0.0;var slow:=elapsed>=4.6
		if elapsed<2.3:cursor=clampf(elapsed-.5,0,1.1)
		elif elapsed<4.6:cursor=clampf(elapsed-2.8,0,1.1)
		else:cursor=clampf((elapsed-5.0)*.5,0,1.1)
		for data in [front,side]:
			pose(data.view,"FP_Torch_Swing",cursor)
			data.view.torch_effects.clock=elapsed;data.view.torch_effects.advance(0)
		var phase:="Ready"
		if cursor>0 and cursor<.25:phase="Pullback"
		elif cursor>=.25 and cursor<26.0/60.0:phase="Strike"
		elif cursor>=26.0/60.0 and cursor<.54:phase="Follow-through"
		elif cursor>=.54 and cursor<1.1:phase="Recovery"
		note.text="%s / %s / %.2f of 1.10 s / visual review pending"%["0.5x speed" if slow else "1x speed",phase,cursor]
		await process_frame;RenderingServer.force_draw(false);RenderingServer.force_draw(false)
		var shot:=canvas.get_texture().get_image()
		if not stills:shot.save_png(OUTPUT+"/frames/%03d.png"%frame)
		if frame in [0,15,22,28,31,36,48]:shot.save_png(OUTPUT+"/pose_%03d.png"%frame)
		if frame%60==0:print("TORCH_ATTACK_PREVIEW frame=",frame)
	canvas.free();front.viewport.free();side.viewport.free();quit()
