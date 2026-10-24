# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func material(color:Color)->StandardMaterial3D:
	var value:=StandardMaterial3D.new();value.albedo_color=color;value.roughness=.9;return value
func run()->void:
	var folder:="res://reports/hammer_shovel"
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder.path_join(".gdignore"),FileAccess.WRITE).store_string("")
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("293943")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7;stage.add_child(environment)
	var sky:=Sky.new();var sky_material:=ProceduralSkyMaterial.new()
	sky_material.sky_top_color=Color("96b4d0");sky_material.sky_horizon_color=Color("e0e6ed")
	sky_material.ground_bottom_color=Color("29333d");sky_material.ground_horizon_color=Color("a6b3bd")
	sky.sky_material=sky_material;environment.environment.sky=sky
	environment.environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-35,0);light.light_energy=1.6;stage.add_child(light)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-25,135,0);fill.light_energy=.55;stage.add_child(fill)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(80,80);floor.mesh=plane
	floor.material_override=material(Color("34444b"));stage.add_child(floor)
	var camera:=Camera3D.new();camera.fov=75;camera.near=.04;camera.position=Vector3(0,1.65,0);camera.current=true;stage.add_child(camera)
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();camera.add_child(tools)
	var view:Node3D=tools.human;tools.set_process(false);view.set_process(false)
	var title:=Label.new();title.position=Vector2(48,30);title.add_theme_font_size_override("font_size",30);root.add_child(title)
	var note:=Label.new();note.position=Vector2(48,78);note.add_theme_font_size_override("font_size",22);root.add_child(note)
	var video:=OS.get_cmdline_user_args().has("--video")
	for item:int in [3,5]:
		var kind:="hammer" if item==3 else "shovel"
		var prefix:="FP_"+kind.capitalize()+"_"
		tools.equip(item)
		var profile:Dictionary=tools.attack_profile()
		title.text="Repair hammer · one-handed strike" if item==3 else "Shovel · two-handed dig and lift"
		var phases:={"ready":0.0,"windup":.333 if item==3 else .3833,"contact":profile.contact,"follow":.55 if item==3 else .6833,"recover":.8 if item==3 else 1.08}
		for phase:String in phases:
			note.text=phase.capitalize()
			view.animation_player.play(view.clips[prefix+"Swing"],0)
			view.animation_player.seek(phases[phase],true);view.animation_player.pause();view.animation_player.advance(0)
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join(kind+"_"+phase+".png"))
		# A third-person view checks both hands and rigid attachment off camera.
		view.set_third_person(true)
		note.text="Third-person ready hold"
		camera.position=Vector3(2.1,1.8,2.7);camera.look_at(Vector3(0,1.1,0))
		tools.reparent(stage);tools.transform=Transform3D.IDENTITY
		view.position=Vector3.ZERO;view.rotation=Vector3.ZERO
		view.animation_player.play(view.clips[prefix+"Idle"],0);view.animation_player.seek(0,true);view.animation_player.pause();view.animation_player.advance(0)
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join(kind+"_third_person.png"))
		tools.reparent(camera);tools.transform=Transform3D.IDENTITY
		camera.position=Vector3(0,1.65,0);camera.rotation=Vector3.ZERO
		view.position=Vector3(0,-1.65,.03);view.rotation=Vector3(0,PI,0);view.set_third_person(false)
		if video:
			var frames:=folder.path_join(kind+"_frames");DirAccess.make_dir_recursive_absolute(frames)
			# Full speed, full speed, then half speed; deterministic timeline capture.
			var segment:float=profile.duration+.7
			for frame:int in roundi((segment*2+profile.duration*2+.9)*30):
				var elapsed:float=frame/30.0;var cursor:=0.0;var slow:bool=elapsed>=segment*2
				if elapsed<segment*2:cursor=maxf(0,fmod(elapsed,segment)-.4)
				else:cursor=maxf(0,(elapsed-segment*2-.4)*.5)
				cursor=minf(cursor,profile.duration)
				note.text="Half speed" if slow else "Full speed"
				view.animation_player.play(view.clips[prefix+"Swing"],0);view.animation_player.seek(cursor,true);view.animation_player.pause();view.animation_player.advance(0)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(frames.path_join("%03d.png"%frame))
	stage.free();title.free();note.free();print("HAMMER_SHOVEL_PREVIEW complete");quit()
