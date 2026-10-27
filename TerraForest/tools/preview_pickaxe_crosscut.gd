# SPDX-License-Identifier: 0BSD
extends "res://tools/preview_pickaxe_fresh.gd"
const CROSSCUT=preload("res://addons/characters/runtime/assets/Human.pickaxe_crosscut.res")
const OUTPUT="res://reports/pickaxe_crosscut"
func setup(candidate:bool,side:bool=false)->Dictionary:
	var data:=panel("side" if side else "fresh");data.viewport.size=Vector2i(1280,720)
	for node in data.viewport.get_children():
		if node is Label:node.queue_free()
	data.candidate=candidate
	if candidate:
		data.view.animation_player.add_animation_library("crosscut",CROSSCUT)
		for name in CROSSCUT.get_animation_list():data.view.clips[String(name)]="crosscut/"+String(name)
	var count:=0
	for node in data.camera.get_parent().get_children():
		if node is MeshInstance3D:
			count+=1
			if count>1:node.queue_free()
	# Fixed target on the camera centerline, independent of the authored tip.
	var point:=Vector3(0,1.65,-.94)
	var target:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.72,.7,.24)
	target.mesh=box;target.material_override=mat(Color("6a7478"));target.position=point+Vector3(0,0,-.12);data.camera.get_parent().add_child(target)
	for axis in 2:
		var mark:=MeshInstance3D.new();var bar:=BoxMesh.new();bar.size=Vector3(.06,.004,.002) if axis==0 else Vector3(.004,.06,.002)
		mark.mesh=bar;mark.material_override=mat(Color("ead3a0"));mark.position=point+Vector3(0,0,.003);data.camera.get_parent().add_child(mark)
	if side:
		data.camera.position=Vector3(1.9,1.7,-2.0);data.camera.look_at(Vector3(0,1.25,-.38));data.camera.fov=54
	else:
		for size in [Vector2(14,2),Vector2(2,14)]:
			var cross:=ColorRect.new();cross.color=Color("fff1c7");cross.size=size;cross.position=Vector2(640,360)-size*.5;data.viewport.add_child(cross)
	return data
func board(left:Dictionary,right:Dictionary,heading:String,right_heading:String)->Dictionary:
	var canvas:=SubViewport.new();canvas.size=Vector2i(2560,820);canvas.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(canvas)
	var bg:=ColorRect.new();bg.size=canvas.size;bg.color=Color("202930");canvas.add_child(bg)
	label(canvas,heading,Vector2(24,15),25);label(canvas,right_heading,Vector2(1304,15),25,Color("e5c99b"))
	for index in 2:
		var picture:=TextureRect.new();picture.texture=([left,right][index] as Dictionary).viewport.get_texture();picture.position=Vector2(index*1280,60);picture.size=Vector2(1280,720);canvas.add_child(picture)
	return {"viewport":canvas,"note":label(canvas,"",Vector2(24,787),19)}
func run()->void:
	for folder in ["comparison_frames","body_frames"]:DirAccess.make_dir_recursive_absolute(OUTPUT+"/"+folder)
	var current:=setup(false);var candidate:=setup(true);var side:=setup(true,true)
	var comparison:=board(current,candidate,"CURRENT DEFAULT / accepted fixed grip","SEPARATE CANDIDATE / tip-first forward-left strike")
	var body_review:=board(candidate,side,"CANDIDATE / first person","CANDIDATE / body and grip mechanics")
	var stills:="--stills" in OS.get_cmdline_user_args()
	var snapshots:={0:"hold",29:"right_load",34:"approach",36:"contact",40:"left_follow",52:"return",67:"hold_again",280:"walk"}
	var frames:Array=snapshots.keys() if stills else range(300)
	for frame:int in frames:
		var elapsed:=frame/30.0;var cursor:=-1.0;var slow:=false
		if elapsed>=.5 and elapsed<2.3:cursor=elapsed-.5
		elif elapsed>=3.0 and elapsed<4.8:cursor=elapsed-3.0
		elif elapsed>=5.4 and elapsed<8.8:cursor=(elapsed-5.4)*.5;slow=true
		for data in [current,candidate,side]:
			var prefix:="FP_Pickaxe_Crosscut_" if data.candidate else "FP_Pickaxe_Fresh_"
			var duration:=1.6 if data.candidate else 1.7
			if elapsed>=8.8:pose(data.view,prefix+"Walk",fmod(elapsed-8.8,1.0))
			elif cursor>=0 and cursor<=duration:pose(data.view,prefix+"Swing",cursor)
			else:pose(data.view,prefix+"Idle",0)
		var note:="%s / candidate frame %03d / both grips fixed / comparison preserves each cycle's timing / not approved as default"%["0.5x speed" if slow else "1x speed",roundi(maxf(0,cursor)*60)]
		comparison.note.text=note;body_review.note.text=note
		await process_frame;RenderingServer.force_draw(false);RenderingServer.force_draw(false)
		for entry in [[comparison,"comparison"],[body_review,"body"]]:
			var shot:Image=entry[0].viewport.get_texture().get_image()
			if not stills:shot.save_png(OUTPUT+"/%s_frames/%03d.png"%[entry[1],frame])
			if snapshots.has(frame):shot.save_png(OUTPUT+"/%s_%s.png"%[entry[1],snapshots[frame]])
		if frame%60==0:print("CROSSCUT_PREVIEW frame=",frame)
	for data in [comparison,body_review,current,candidate,side]:data.viewport.free()
	quit()
