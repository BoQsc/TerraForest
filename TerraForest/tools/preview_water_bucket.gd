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
	var front:=panel("fresh");var side:=panel("side")
	for data in [front,side]:
		var stage:Node=data.camera.get_parent();var count:=0
		for child in stage.get_children():
			if child is MeshInstance3D:
				count+=1
				if count>1:child.queue_free()
		for child in data.viewport.get_children():
			if child is Label:child.queue_free()
		data.viewport.size=Vector2i(960,600);data.view.equip(411);lighting(stage)
	var showcase:=SubViewport.new();showcase.size=Vector2i(960,600);showcase.own_world_3d=true;showcase.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(showcase)
	var world:=WorldEnvironment.new();world.environment=Environment.new();world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color("30383e")
	world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color.WHITE;world.environment.ambient_light_energy=.65;showcase.add_child(world);lighting(showcase)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-35,-35,0);light.light_energy=1.5;showcase.add_child(light)
	var item:=MeshInstance3D.new();item.mesh=preload("res://addons/volumetric_water/bucket_model.gd").mesh();showcase.add_child(item)
	var camera:=Camera3D.new();camera.position=Vector3(.43,.36,.65);camera.look_at_from_position(camera.position,Vector3(0,.03,0));camera.fov=38;camera.current=true;showcase.add_child(camera)
	var viewport:=SubViewport.new();viewport.size=Vector2i(1920,1260);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var background:=ColorRect.new();background.size=Vector2(1920,1260);background.color=Color("202930");viewport.add_child(background)
	var caption:=label(viewport,"WATER BUCKET / BLENDER PBR + CHARACTER CARRY GRIP",Vector2(22,14),26)
	for entry in [[front.viewport,Vector2(0,60)],[showcase,Vector2(960,60)],[side.viewport,Vector2(0,660)]]:
		var picture:=TextureRect.new();picture.position=entry[1];picture.size=Vector2(960,600);picture.texture=entry[0].get_texture();viewport.add_child(picture)
	var note:=label(viewport,"",Vector2(1010,720),27)
	var frames:Array=range(180) if OS.get_cmdline_user_args().has("--video") else [0,30,60,90,120,150]
	for frame:int in frames:
		var elapsed:=frame/30.0;var clip:="Idle";var cursor:=0.0;var filled:=true
		if elapsed>=1 and elapsed<2:clip="Walk";cursor=elapsed-1
		elif elapsed>=2 and elapsed<3.2:clip="Pour";cursor=elapsed-2;filled=false
		elif elapsed>=3.5 and elapsed<4.5:clip="Scoop";cursor=elapsed-3.5
		elif elapsed>=4.5:clip="Run";cursor=fmod(elapsed-4.5,.8)
		for data in [front,side]:
			data.view.equip(411 if filled else 401);pose(data.view,"FP_Bucket_"+clip,cursor)
		note.text="%s / %s\n\n16,700 triangles\nRolled metal rim and foot\nRounded bail + wooden grip\n1024px embedded PBR maps\n\nAppearance awaiting playtest"%[clip,"FULL" if filled else "EMPTY"]
		await process_frame;RenderingServer.force_draw(false);RenderingServer.force_draw(false)
		var picture:Image=viewport.get_texture().get_image()
		if OS.get_cmdline_user_args().has("--video"):picture.save_png(OUTPUT+"/frames/%03d.png"%frame)
		if frame in [0,30,60,90,120,150]:picture.save_png(OUTPUT+"/pose-%03d.png"%frame)
	viewport.free();front.viewport.free();side.viewport.free();showcase.free();print("BUCKET_PREVIEW complete");quit()
