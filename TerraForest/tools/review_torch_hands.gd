# SPDX-License-Identifier: 0BSD
extends "res://tools/preview_pickaxe_fresh.gd"
const OUTPUT="res://reports/torch_hands"
func close_view(side:String,offset:Vector3)->Dictionary:
	var data:=panel("side");data.viewport.size=Vector2i(640,480);data.view.equip(6)
	data.view.torch_effects.set_burning(false)
	for node in data.viewport.get_children():
		if node is Label:node.queue_free()
	for node in data.camera.get_parent().get_children():
		if node is MeshInstance3D:node.queue_free()
	data.side=side;data.offset=offset
	return data
func run()->void:
	DirAccess.make_dir_recursive_absolute(OUTPUT);FileAccess.open(OUTPUT+"/.gdignore",FileAccess.WRITE).store_string("")
	var views:=[close_view("Right",Vector3(.05,.10,-.40)),close_view("Right",Vector3(.38,.12,.03)),close_view("Right",Vector3(-.32,.10,.05)),close_view("Left",Vector3(.30,.10,-.20))]
	var canvas:=SubViewport.new();canvas.size=Vector2i(1280,1020);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var bg:=ColorRect.new();bg.size=canvas.size;bg.color=Color("202930");canvas.add_child(bg)
	var note:=label(canvas,"",Vector2(20,12),24)
	for i in 4:
		var picture:=TextureRect.new();picture.texture=views[i].viewport.get_texture();picture.position=Vector2((i%2)*640,60+(i/2)*480);picture.size=Vector2(640,480);canvas.add_child(picture)
	var records:={};var tag:="before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tag="):tag=arg.trim_prefix("--tag=")
	for entry in [["Idle",0.0],["Walk",.25],["Run",.4],["Jump",.75],["Crouch",0.0],["Equip",.16]]:
		for data in views:
			pose(data.view,"FP_Torch_"+entry[0],entry[1])
			var skeleton:Skeleton3D=data.view.model.find_children("*","Skeleton3D",true,false)[0]
			var hand:Transform3D=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone(data.side+"Hand"))
			var aim:=hand.origin+hand.basis.y*.055
			data.camera.position=aim+data.offset;data.camera.fov=38;data.camera.look_at(aim)
		note.text="%s / %s %.2f s — right: front / side / palm; left: relaxed hand"%[tag,entry[0],entry[1]]
		await process_frame;RenderingServer.force_draw(false);RenderingServer.force_draw(false)
		canvas.get_texture().get_image().save_png(OUTPUT+"/%s_%s.png"%[tag,entry[0]])
	var data:Dictionary=views[0];var skeleton:Skeleton3D=data.view.model.find_children("*","Skeleton3D",true,false)[0]
	for suffix:String in ["Idle","Walk","Run","Jump","Crouch","Equip"]:
		var animation:Animation=data.view.animation_player.get_animation(data.view.clips["FP_Torch_"+suffix])
		var rows:Array=[]
		for frame in roundi(animation.length*60)+1:
			pose(data.view,"FP_Torch_"+suffix,frame/60.0)
			var row:={"frame":frame}
			for side:String in ["Left","Right"]:
				var hand:=skeleton.get_bone_global_pose(skeleton.find_bone(side+"Hand"))
				var elbow:=skeleton.get_bone_global_pose(skeleton.find_bone(side+"ForeArm"))
				row[side]={"wrist_bend":rad_to_deg((hand.origin-elbow.origin).angle_to(hand.basis.y)),"hand":str(hand),"forearm":str(elbow)}
			rows.append(row)
		records[suffix]=rows
	FileAccess.open(OUTPUT+"/"+tag+"_joints.json",FileAccess.WRITE).store_string(JSON.stringify(records,"  "))
	canvas.free()
	for data_view in views:data_view.viewport.free()
	quit()
