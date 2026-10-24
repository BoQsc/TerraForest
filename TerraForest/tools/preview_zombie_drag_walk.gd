# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func material(color:Color)->StandardMaterial3D:
	var value:=StandardMaterial3D.new();value.albedo_color=color;value.roughness=.9;return value
func run()->void:
	var stage:=Node3D.new();root.add_child(stage)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("253541")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65;stage.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-45,-35,0);light.light_energy=1.5;light.shadow_enabled=true;stage.add_child(light)
	var fill:=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-35,130,0);fill.light_energy=.45;stage.add_child(fill)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(60,60);floor.mesh=plane;floor.material_override=material(Color("35454c"));stage.add_child(floor)
	for n in range(-14,15):
		for axis in 2:
			var line:=MeshInstance3D.new();var shape:=BoxMesh.new();shape.size=Vector3(.012,.002,40) if axis==0 else Vector3(40,.002,.012)
			line.mesh=shape;line.material_override=material(Color("53636b"));line.position=Vector3(n,.001,0) if axis==0 else Vector3(0,.001,n);stage.add_child(line)
	var zombie=preload("res://addons/characters/runtime/zombie.gd").new();stage.add_child(zombie);zombie.set_physics_process(false);zombie.set_behavior(false)
	var camera:=Camera3D.new();camera.fov=48;camera.near=.05;camera.current=true;stage.add_child(camera)
	var title:=Label.new();title.position=Vector2(60,40);title.add_theme_font_size_override("font_size",30);root.add_child(title)
	var note:=Label.new();note.text="Planted left step · delayed right toe scrape · uneven weight transfer";note.position=Vector2(60,92);note.add_theme_font_size_override("font_size",20);root.add_child(note)
	var folder:="res://reports/zombie_drag_walk/preview_frames";DirAccess.make_dir_recursive_absolute(folder)
	for frame in 360:
		var slow:=frame>=240
		var elapsed:=float(frame)/30.0 if not slow else 8.0+float(frame-240)/60.0
		zombie.position=Vector3(0,0,.45*elapsed)
		zombie._play_animation("Zombie_Walk_Drag_Right",true)
		zombie.animation_player.seek(fmod(elapsed,2),true);zombie.animation_player.advance(0)
		var side:=frame>=120
		var view:=Vector3(3.1,1.25,.1) if side else Vector3(2.1,1.6,2.9)
		camera.position=zombie.position+view;camera.look_at(zombie.position+Vector3.UP*.90)
		title.text="Weighted limp · side · half speed" if slow else "Weighted limp · side · normal speed" if side else "Weighted limp · normal speed"
		await RenderingServer.frame_post_draw
		var picture:=root.get_texture().get_image();picture.save_png(folder+"/%03d.png"%frame)
		if frame in [21,51,83,144,171]:picture.save_png("res://reports/zombie_drag_walk/pose_%03d.png"%frame)
	stage.free();title.free();note.free();print("ZOMBIE_DRAG_PREVIEW frames=360");quit()
