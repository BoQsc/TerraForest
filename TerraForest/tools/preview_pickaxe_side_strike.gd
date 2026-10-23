# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func material(color:Color)->StandardMaterial3D:
	var value:=StandardMaterial3D.new();value.albedo_color=color;value.roughness=.9;return value
func run()->void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	var capture:=SubViewport.new();capture.size=Vector2i(1920,1080);capture.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(capture)
	var stage:=Node3D.new();capture.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("293943")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7;stage.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-35,0);light.light_energy=1.6;stage.add_child(light)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-25,135,0);fill.light_energy=.55;stage.add_child(fill)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(80,80);floor.mesh=plane
	floor.material_override=material(Color("34444b"));stage.add_child(floor)
	var camera:=Camera3D.new();camera.fov=75;camera.near=.04;camera.position=Vector3(0,1.68,0);camera.current=true;stage.add_child(camera)
	# Fixed studio target: the working point approaches this face in depth.
	var target:=MeshInstance3D.new();var block:=BoxMesh.new();block.size=Vector3(.64,.64,.24)
	target.mesh=block;target.material_override=material(Color("607078"));target.position=Vector3(0,1.68,-1.14);stage.add_child(target)
	for axis in 2:
		var mark:=MeshInstance3D.new();var bar:=BoxMesh.new();bar.size=Vector3(.07,.006,.002) if axis==0 else Vector3(.006,.07,.002)
		mark.mesh=bar;mark.material_override=material(Color("dcc6a0"));mark.position=Vector3(.16,1.68,-1.018);stage.add_child(mark)
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(tools)
	var view:Node3D=tools.human;tools.equip(1);tools.set_process(false);view.set_process(false)
	var library:=preload("res://addons/characters/runtime/assets/Human.pickaxe_side_strike.res")
	view.animation_player.add_animation_library("side_strike",library)
	for name in library.get_animation_list():view.clips[String(name)]="side_strike/"+String(name)
	var title:=Label.new();title.position=Vector2(56,36);title.add_theme_font_size_override("font_size",30);title.text="Separate copy · strike from the right side";capture.add_child(title)
	var note:=Label.new();note.position=Vector2(56,84);note.add_theme_font_size_override("font_size",22);capture.add_child(note)
	var folder:="res://reports/pickaxe_side_strike/preview_frames";DirAccess.make_dir_recursive_absolute(folder)
	var stills:=OS.get_cmdline_user_args().has("--stills")
	var snapshots:={0:"ready",34:"chamber_right",37:"side_approach",40:"strike",43:"follow_forward",59:"ready_again"}
	var count:=60 if stills else 240
	for frame in count:
		var elapsed:=float(frame)/30.0;var cursor:=-1.0;var slow:=false
		if elapsed>=.8 and elapsed<2.0:cursor=elapsed-.8
		elif elapsed>=2.8 and elapsed<4.0:cursor=elapsed-2.8
		elif elapsed>=4.8 and elapsed<7.2:cursor=(elapsed-4.8)*.5;slow=true
		var clip:="FP_Pickaxe_Diagonal_Idle" if cursor<0 else "FP_Pickaxe_SideStrike_Swing"
		view.animation_player.play(view.clips[clip],0)
		view.animation_player.seek(fmod(elapsed,3.0) if cursor<0 else cursor,true)
		view.animation_player.pause();view.animation_player.advance(0)
		var phase:="Ready · left hand lower / right hand upper"
		if cursor>=0:
			if cursor<.34:phase="Draw back beside the right shoulder"
			elif cursor<.635:phase="Drive forward diagonally from the side"
			elif cursor<.72:phase="Short follow-through in front"
			else:phase="Recover to the diagonal ready hold"
		note.text=phase+(" · half speed" if slow else "")
		await process_frame
		RenderingServer.force_draw(false)
		var picture:=capture.get_texture().get_image()
		if not stills:picture.save_png(folder+"/%03d.png"%frame)
		if snapshots.has(frame):picture.save_png("res://reports/pickaxe_side_strike/"+snapshots[frame]+".png")
	capture.free();print("PICKAXE_SIDE_STRIKE_PREVIEW frames=",count);quit()
