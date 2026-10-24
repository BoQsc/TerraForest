# SPDX-License-Identifier: 0BSD
extends SceneTree
const LIBRARY = preload("res://addons/characters/runtime/assets/Human.pickaxe_fresh.res")
const FOLDER = "res://reports/pickaxe_fresh"
var panels:Array[Dictionary]=[]
func _initialize()->void:run.call_deferred()
func mat(color:Color)->StandardMaterial3D:
	var result:=StandardMaterial3D.new();result.albedo_color=color;result.roughness=.88;return result
func label(parent:Node,text:String,where:Vector2,size:int,color:Color=Color.WHITE)->Label:
	var result:=Label.new();result.position=where;result.text=text;result.add_theme_font_size_override("font_size",size)
	result.add_theme_color_override("font_color",color);parent.add_child(result);return result
func panel(kind:String)->Dictionary:
	var viewport:=SubViewport.new();viewport.size=Vector2i(1280,720);viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var stage:=Node3D.new();viewport.add_child(stage)
	var world:=WorldEnvironment.new();world.environment=Environment.new();world.environment.background_mode=Environment.BG_COLOR
	world.environment.background_color=Color("30383e");world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color=Color.WHITE;world.environment.ambient_light_energy=.75;stage.add_child(world)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-35,0);light.light_energy=1.6;stage.add_child(light)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-25,135,0);fill.light_energy=.55;stage.add_child(fill)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(30,30);floor.mesh=plane;floor.material_override=mat(Color("566168"));stage.add_child(floor)
	var camera:=Camera3D.new();camera.fov=75;camera.near=.035;camera.position=Vector3(0,1.65,0);camera.current=true;stage.add_child(camera)
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(tools)
	tools.equip(1);tools.set_process(false);var view:Node3D=tools.human;view.set_process(false)
	if kind!="current" and not view.clips.has("FP_Pickaxe_Fresh_Swing"):
		view.animation_player.add_animation_library("fresh_review",LIBRARY)
		for name in LIBRARY.get_animation_list():view.clips[String(name)]="fresh_review/"+String(name)
	if kind=="side":
		tools.reparent(stage);tools.transform=Transform3D.IDENTITY
		view.position=Vector3(0,0,.03);view.rotation=Vector3(0,PI,0);view.set_third_person(true)
		camera.position=Vector3(2.5,1.65,-1.65);camera.fov=50;camera.look_at(Vector3(0,1.22,-.26))
	# A fixed neutral target makes the authored stroke readable without VFX.
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://addons/characters/authoring/Human.pickaxe_fresh.json"))
	var contact:Array=source.samples[50].working_tip
	var point:=Vector3(-float(contact[0]),float(contact[2]),float(contact[1])+.03)
	var block:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.62,point.y+.1,.28);block.mesh=box
	block.material_override=mat(Color("778189"));block.position=Vector3(point.x,box.size.y*.5,point.z-.14);stage.add_child(block)
	for axis in 2:
		var mark:=MeshInstance3D.new();var bar:=BoxMesh.new();bar.size=Vector3(.06,.004,.002) if axis==0 else Vector3(.004,.06,.002)
		mark.mesh=bar;mark.material_override=mat(Color("d3c49b"));mark.position=point+Vector3(0,0,.002);stage.add_child(mark)
	var title:={"fresh":"FIRM GRIP / FIRST PERSON","side":"FIRM GRIP / BODY MECHANICS","current":"PREVIOUS DEFAULT / FIRST PERSON"}
	label(viewport,title[kind],Vector2(28,22),24,Color("c6d6d5"))
	var note:=label(viewport,"",Vector2(28,59),21)
	return {"viewport":viewport,"view":view,"note":note,"camera":camera,"kind":kind}
func composite(left:Dictionary,right:Dictionary,title:String)->Dictionary:
	var viewport:=SubViewport.new();viewport.size=Vector2i(2560,860);viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	var bg:=ColorRect.new();bg.size=Vector2(2560,860);bg.color=Color("1e272d");viewport.add_child(bg)
	label(viewport,title,Vector2(30,18),29)
	for index in 2:
		var picture:=TextureRect.new();picture.texture=([left,right][index] as Dictionary).viewport.get_texture()
		picture.position=Vector2(index*1280,70);picture.size=Vector2(1280,720);viewport.add_child(picture)
	var line:=ColorRect.new();line.size=Vector2(4,720);line.position=Vector2(1278,70);line.color=Color("1e272d");viewport.add_child(line)
	var note:=label(viewport,"",Vector2(30,810),23)
	label(viewport,"FIXED GRIP / ACCEPTED 2026-10-24",Vector2(1910,814),22,Color("b7c5cb"))
	return {"viewport":viewport,"note":note}
func pose(view:Node,clip:String,time:float)->void:
	view.animation_player.play(view.clips[clip],0);view.animation_player.seek(time,true);view.animation_player.pause();view.animation_player.advance(0)
func run()->void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	DirAccess.make_dir_recursive_absolute(FOLDER);FileAccess.open(FOLDER+"/.gdignore",FileAccess.WRITE).store_string("")
	for folder in ["blockout_frames","comparison_frames","first_person_frames"]:DirAccess.make_dir_recursive_absolute(FOLDER+"/"+folder)
	panels=[panel("fresh"),panel("side"),panel("current")]
	var main:=composite(panels[0],panels[1],"PICKAXE / FIRM GRIP - BOTH HANDS FIXED ON THE SHAFT")
	var comparison:=composite(panels[2],panels[0],"PICKAXE / CURRENT AND FIRM-GRIP BLOCKOUT - EACH AT ITS OWN TIMING")
	var stills:=OS.get_cmdline_user_args().has("--stills")
	var snapshots:={0:"ready",27:"lift",31:"loaded",36:"drop",40:"contact",42:"settle",51:"return",66:"ready_again"}
	var frames:Array=snapshots.keys() if stills else range(300)
	for frame:int in frames:
		var elapsed:=frame/30.0;var cursor:=0.0;var slow:=false
		if elapsed<2.5:cursor=maxf(0,elapsed-.5)
		elif elapsed<5:cursor=maxf(0,elapsed-3)
		else:cursor=maxf(0,(elapsed-5.5)*.5);slow=true
		cursor=minf(1.7,cursor)
		for data in panels:
			var current:bool=data.kind=="current"
			pose(data.view,"FP_Pickaxe_SidePullback_Swing" if current else "FP_Pickaxe_Fresh_Swing",minf(cursor,1.2) if current else cursor)
			data.note.text=("0.5x speed" if slow else "1x speed")+" / "+("1.2 s cycle" if current else "1.7 s cycle")
		var phase:="Ready"
		if cursor>0 and cursor<.53:phase="Lift / firm fixed grip"
		elif cursor>=.53 and cursor<.833:phase="Downstroke / firm fixed grip"
		elif cursor>=.833 and cursor<1.0:phase="Contact / settle"
		elif cursor>=1.0 and cursor<1.7:phase="Return / firm fixed grip"
		main.note.text=phase+" / New pose %03d of 102"%roundi(cursor*60)
		comparison.note.text="Both hands stay fixed throughout the new swing and recovery"
		await process_frame;RenderingServer.force_draw(false);RenderingServer.force_draw(false)
		var main_image:Image=main.viewport.get_texture().get_image()
		if not stills:
			main_image.save_png(FOLDER+"/blockout_frames/%03d.png"%frame)
			comparison.viewport.get_texture().get_image().save_png(FOLDER+"/comparison_frames/%03d.png"%frame)
			panels[0].viewport.get_texture().get_image().save_png(FOLDER+"/first_person_frames/%03d.png"%frame)
		if snapshots.has(frame):main_image.save_png(FOLDER+"/"+snapshots[frame]+".png")
		if frame%60==0:print("PICKAXE_FRESH_PREVIEW frame=",frame)
	main.viewport.free();comparison.viewport.free()
	for data in panels:data.viewport.free()
	print("PICKAXE_FRESH_PREVIEW complete samples=",frames.size());quit()
