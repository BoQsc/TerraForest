# SPDX-License-Identifier: 0BSD
extends "res://tools/preview_pickaxe_fresh.gd"
const OUTPUT="res://reports/water_bucket_visuals"
func lighting(stage:Node)->void:
	for node in stage.get_children():
		if node is WorldEnvironment:
			var sky:=ProceduralSkyMaterial.new();sky.sky_top_color=Color("526878");sky.sky_horizon_color=Color("c0c7c8");sky.ground_bottom_color=Color("333c43");sky.ground_horizon_color=Color("c0c7c8")
			node.environment.sky=Sky.new();node.environment.sky.sky_material=sky
			node.environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUTPUT+"/frames")
	var front:=panel("fresh");var side:=panel("side");var close:=panel("side")
	for data in [front,side,close]:
		var stage:Node=data.camera.get_parent();var count:=0
		for child in stage.get_children():
			if child is MeshInstance3D:
				count+=1
				if count>1:child.queue_free()
		for child in data.viewport.get_children():
			if child is Label:child.queue_free()
		data.viewport.size=Vector2i(960,600);data.view.equip(411);lighting(stage)
	close.camera.position=Vector3(-.65,1.30,-.97);close.camera.fov=52;close.camera.look_at(Vector3(0,1.35,-.35))
	var viewport:=SubViewport.new();viewport.size=Vector2i(1920,1260);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var background:=ColorRect.new();background.size=Vector2(1920,1260);background.color=Color("202930");viewport.add_child(background)
	label(viewport,"BUCKET REWORK / OVERHAND GRIP + TWO-HAND SCOOP AND POUR",Vector2(22,14),26)
	for entry in [[front.viewport,Vector2(0,60)],[close.viewport,Vector2(960,60)],[side.viewport,Vector2(0,660)]]:
		var picture:=TextureRect.new();picture.position=entry[1];picture.size=Vector2(960,600);picture.texture=entry[0].get_texture();viewport.add_child(picture)
	var note:=label(viewport,"",Vector2(1010,720),27)
	var stills:=[0,41,60,72,88,144,158,170,188,225]
	var frames:Array=range(300) if OS.get_cmdline_user_args().has("--video") else stills
	for frame:int in frames:
		var elapsed:=frame/30.0;var clip:="Idle";var cursor:=0.0;var filled:=true
		if elapsed>=.8 and elapsed<3.6:clip="Pour";cursor=elapsed-.8;filled=cursor<.8
		elif elapsed>=3.6 and elapsed<4.2:filled=false
		elif elapsed>=4.2 and elapsed<6.6:clip="Scoop";cursor=elapsed-4.2;filled=cursor>1.4
		elif elapsed>=7 and elapsed<8:clip="Walk";cursor=elapsed-7
		elif elapsed>=8 and elapsed<8.8:clip="Run";cursor=elapsed-8
		for data in [front,side,close]:
			if clip in ["Pour","Scoop"]:
				data.view.equip(401,1000000 if clip=="Pour" else 0)
				data.view.equip(401,0 if clip=="Pour" else 1000000)
				data.view.bucket_use(clip=="Pour")
			else:data.view.equip(411 if filled else 401)
			pose(data.view,"FP_Bucket_"+clip,cursor);data.view._sync_bucket_water()
		note.text="%s / %.2f s\n\nOverhand carry grip\nPail pivots at bail ears\nLeft palm supports the base\nReach / dip / lift\nSupport / tip / hold / recover\n\nRevision awaiting your review"%[clip,cursor]
		await process_frame;RenderingServer.force_draw(false);RenderingServer.force_draw(false)
		var picture:Image=viewport.get_texture().get_image()
		if OS.get_cmdline_user_args().has("--video"):picture.save_png(OUTPUT+"/frames/%03d.png"%frame)
		if frame in stills:picture.save_png(OUTPUT+"/pose-%03d.png"%frame)
	viewport.free();front.viewport.free();side.viewport.free();close.viewport.free();print("BUCKET_PREVIEW complete");quit()
