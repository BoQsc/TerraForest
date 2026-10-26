# SPDX-License-Identifier: 0BSD
extends "res://tools/review_torch_hands.gd"
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUTPUT+"/motion_frames")
	var front:=panel("fresh");front.viewport.size=Vector2i(960,720);front.view.equip(6)
	front.view.torch_effects.set_process(false)
	for node in front.viewport.get_children():
		if node is Label:node.queue_free()
	var closeups:=[close_view("Right",Vector3(.05,.10,-.40)),close_view("Right",Vector3(-.32,.10,.05))]
	for data in closeups:data.viewport.size=Vector2i(640,360)
	var canvas:=SubViewport.new();canvas.size=Vector2i(1600,820);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var bg:=ColorRect.new();bg.size=canvas.size;bg.color=Color("202930");canvas.add_child(bg)
	label(canvas,"TORCH / REBUILT HAND GRIP",Vector2(24,14),27)
	label(canvas,"Runtime close-ups / fire hidden to inspect fingers",Vector2(975,20),20)
	var note:=label(canvas,"",Vector2(24,783),20)
	for entry in [[front,Vector2(0,60),Vector2(960,720)],[closeups[0],Vector2(960,60),Vector2(640,360)],[closeups[1],Vector2(960,420),Vector2(640,360)]]:
		var picture:=TextureRect.new();picture.texture=entry[0].viewport.get_texture();picture.position=entry[1];picture.size=entry[2];canvas.add_child(picture)
	for frame in 300:
		var elapsed:=frame/30.0;var clip:="Idle";var cursor:=fmod(elapsed,3.0)
		if elapsed<.45:clip="Equip";cursor=elapsed
		elif elapsed<2:cursor=elapsed-.45
		elif elapsed<4:clip="Walk";cursor=fmod(elapsed-2,1.0)
		elif elapsed<5.6:clip="Run";cursor=fmod(elapsed-4,.8)
		elif elapsed<7.1:clip="Jump";cursor=elapsed-5.6
		elif elapsed<8.1:clip="Crouch";cursor=elapsed-7.1
		for data in [front]+closeups:
			pose(data.view,"FP_Torch_"+clip,cursor)
			if data==front:continue
			var skeleton:Skeleton3D=data.view.model.find_children("*","Skeleton3D",true,false)[0]
			var hand:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))
			var aim:=hand.origin+hand.basis.y*.055
			data.camera.position=aim+data.offset;data.camera.fov=38;data.camera.look_at(aim)
		front.view.torch_effects.clock=elapsed;front.view.torch_effects.advance(0)
		note.text="%s / %.2f s / normal speed / fixed grip / hand revision awaiting player review"%[clip,cursor]
		await process_frame;RenderingServer.force_draw(false);RenderingServer.force_draw(false)
		var shot:=canvas.get_texture().get_image();shot.save_png(OUTPUT+"/motion_frames/%03d.png"%frame)
		if frame in [0,5,30,75,135,190,225]:shot.save_png(OUTPUT+"/motion_%03d.png"%frame)
		if frame%60==0:print("TORCH_HAND_PREVIEW frame=",frame)
	canvas.free();front.viewport.free()
	for data in closeups:data.viewport.free()
	quit()
