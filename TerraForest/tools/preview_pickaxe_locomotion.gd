# SPDX-License-Identifier: 0BSD
extends "res://tools/preview_pickaxe_fresh.gd"
const OUTPUT="res://reports/pickaxe_locomotion"
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUTPUT+"/frames")
	var front:=panel("fresh");var side:=panel("side")
	# Remove the swing fixture's target; show carriage with open space ahead.
	for data in [front,side]:
		var stage:Node=data.camera.get_parent()
		var surfaces:=0
		for child in stage.get_children():
			if child is MeshInstance3D:
				surfaces+=1
				if surfaces>1:child.queue_free()
		data.viewport.size=Vector2i(800,450)
		for child in data.viewport.get_children():
			if child is Label:child.queue_free()
		scene_props(stage)
		var body:=CharacterBody3D.new();stage.add_child(body);data.view.body=body
		data.view.equip(1)
	var viewport:=SubViewport.new();viewport.size=Vector2i(1600,510);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var bg:=ColorRect.new();bg.size=Vector2(1600,510);bg.color=Color("202930");viewport.add_child(bg)
	var caption:=label(viewport,"",Vector2(22,14),23)
	for index in 2:
		var picture:=TextureRect.new();picture.position=Vector2(index*800,60);picture.size=Vector2(800,450)
		picture.texture=[front,side][index].viewport.get_texture();viewport.add_child(picture)
	for frame in 180:
		var elapsed:=frame/30.0
		var speed:=0.0 if elapsed<.5 or elapsed>=4.5 else (3.0 if elapsed<2.5 else 7.0)
		var mode:="IDLE" if speed==0 else ("WALK" if speed<5 else "RUN")
		caption.text="PICKAXE / "+mode+" / 1x speed - fixed hands, movement from the accepted hold"
		for data in [front,side]:
			data.view.body.velocity=Vector3(0,0,speed)
			data.view._process(1.0/30.0)
		await process_frame;RenderingServer.force_draw(false);RenderingServer.force_draw(false)
		viewport.get_texture().get_image().save_png(OUTPUT+"/frames/%03d.png"%frame)
		if frame in [30,38,90]:viewport.get_texture().get_image().save_png(OUTPUT+"/pose-%03d.png"%frame)
		if frame%60==0:print("LOCOMOTION_PREVIEW frame=",frame)
	viewport.free();front.viewport.free();side.viewport.free();quit()
func scene_props(stage:Node)->void:
	for index in 5:
		var post:=MeshInstance3D.new();var shape:=BoxMesh.new();shape.size=Vector3(.08,2,.08);post.mesh=shape
		post.position=Vector3(-2+index,1,-3);post.material_override=mat(Color("69747c"));stage.add_child(post)
