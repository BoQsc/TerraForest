# SPDX-License-Identifier: 0BSD
extends "res://tools/preview_pickaxe_fresh.gd"
const OUTPUT="res://reports/wooden_torch"
func setup(kind:String)->Dictionary:
	var data:=panel(kind);var stage:Node=data.camera.get_parent();var count:=0
	for child in stage.get_children():
		if child is MeshInstance3D:
			count+=1
			if count>1:child.queue_free()
			else:child.material_override=mat(Color("4e504b"))
		if child is WorldEnvironment:
			child.environment.background_color=Color("101b24")
			child.environment.ambient_light_color=Color("889fb1");child.environment.ambient_light_energy=.16
			child.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
			child.environment.glow_enabled=true;child.environment.glow_intensity=.5;child.environment.glow_bloom=.04
		if child is DirectionalLight3D:child.light_energy=.18;child.light_color=Color("9eafca")
	for child in data.viewport.get_children():
		if child is Label:child.queue_free()
	data.view.equip(6);data.view.torch_effects.set_process(false)
	for i in 11:
		var stone:=MeshInstance3D.new();var block:=BoxMesh.new();block.size=Vector3(.7,.42,.5)
		stone.mesh=block;stone.material_override=mat(Color("6d7476"));stone.position=Vector3((i%4-1.5)*.72,.21+floori(i/4.0)*.44,-2.4)
		stage.add_child(stone)
	return data
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUTPUT+"/frames")
	FileAccess.open(OUTPUT+"/.gdignore",FileAccess.WRITE).store_string("")
	var front:=setup("fresh");var side:=setup("side")
	front.viewport.size=Vector2i(1280,720);side.viewport.size=Vector2i(640,720)
	side.camera.position=Vector3(1.22,1.48,-1.30);side.camera.fov=48;side.camera.look_at(Vector3(.15,1.58,-.35))
	var viewport:=SubViewport.new();viewport.size=Vector2i(1920,820);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var bg:=ColorRect.new();bg.size=Vector2(1920,820);bg.color=Color("10191f");viewport.add_child(bg)
	label(viewport,"WOODEN TORCH",Vector2(28,14),29,Color("edc798"))
	label(viewport,"First-person carry / warm local light",Vector2(320,20),22,Color("afb8bc"))
	label(viewport,"Grip and material detail",Vector2(1310,20),22,Color("afb8bc"))
	for entry in [[front,Vector2(0,60),Vector2(1280,720)],[side,Vector2(1280,60),Vector2(640,720)]]:
		var picture:=TextureRect.new();picture.texture=entry[0].viewport.get_texture();picture.position=entry[1];picture.size=entry[2];viewport.add_child(picture)
	var note:=label(viewport,"",Vector2(28,787),20,Color("afb8bc"))
	var frames:Array=range(240) if "--video" in OS.get_cmdline_user_args() else [0,35,100,155]
	for frame:int in frames:
		var elapsed:=frame/30.0;var clip:="Idle";var cursor:=fmod(elapsed,3.0)
		if elapsed>=3 and elapsed<5:clip="Walk";cursor=fmod(elapsed-3,1.0)
		elif elapsed>=5 and elapsed<6:clip="Run";cursor=fmod(elapsed-5,.8)
		for data in [front,side]:
			pose(data.view,"FP_Torch_"+clip,cursor)
			data.view.torch_effects.clock=elapsed;data.view.torch_effects.advance(0)
		note.text="%s / fixed hand grip · layered linen · charred wood · flame, embers and smoke     |     First draft — awaiting review"%clip
		await process_frame;RenderingServer.force_draw(false);RenderingServer.force_draw(false)
		var image:Image=viewport.get_texture().get_image()
		if "--video" in OS.get_cmdline_user_args():image.save_png(OUTPUT+"/frames/%03d.png"%frame)
		if frame in [0,35,100,155]:image.save_png(OUTPUT+"/preview_%03d.png"%frame)
		if frame%60==0:print("TORCH_PREVIEW frame=",frame)
	viewport.free();front.viewport.free();side.viewport.free();quit()
