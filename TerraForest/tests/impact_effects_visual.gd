# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:run.call_deferred()
func run()->void:
	var folder:="res://reports/impact_effects/visual"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--effects-evidence="):folder=arg.trim_prefix("--effects-evidence=")
	DirAccess.make_dir_recursive_absolute(folder)
	var scene:=Node3D.new();root.add_child(scene)
	var world:=WorldEnvironment.new();world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color(.025,.035,.045)
	world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color(.6,.65,.7);world.environment.ambient_light_energy=.7;scene.add_child(world)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-55,-20,0);sun.light_energy=1.7;scene.add_child(sun)
	var camera:=Camera3D.new();scene.add_child(camera);camera.position=Vector3(0,2.6,4.5);camera.look_at(Vector3(0,.5,0));camera.fov=48;camera.make_current()
	var effects=load("res://addons/impact_effects/impact_effects.gd").new();effects.settings_path="";scene.add_child(effects)
	var positions:Array[Vector3]=[Vector3(-1.5,.65,0),Vector3(0,.1,0),Vector3(1.5,.1,0)]
	var materials:=["metal","soil","stone"]
	for i in 3:
		var block:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(.9,.12 if i else 1,.7);block.mesh=box
		block.position=Vector3(positions[i].x,.03 if i else .5,-.38 if i==0 else 0)
		var material:=StandardMaterial3D.new();material.albedo_color=Color("444d55") if i==0 else (Color("493c32") if i==1 else Color("565d60"));material.roughness=.85;material.metallic=.7 if i==0 else 0.0
		block.material_override=material;scene.add_child(block)
		var label:=Label3D.new();label.text=["METAL / SPARKS","TOPSOIL / CLODS","STONE / CHIPS"][i];label.font_size=36;label.pixel_size=.0018;label.position=Vector3(positions[i].x,1.55,0);scene.add_child(label)
	# Warm shaders once; the actual timed sequence starts after these expire.
	for i in 3:effects.burst(positions[i],Vector3.BACK if i==0 else Vector3.UP,materials[i],i!=0)
	await create_timer(1.4).timeout
	for i in 3:effects.burst(positions[i],Vector3.BACK if i==0 else Vector3.UP,materials[i],i!=0)
	var previous:=0.0
	for time in [.05,.12,.22,.36,.52,.72,.98,1.3]:
		await create_timer(time-previous).timeout;previous=time
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("frame_%03d.png"%int(time*1000)))
	var ok:bool=effects.statistics().active==0
	scene.free();await process_frame;await process_frame
	print("IMPACT_EFFECTS_VISUAL failures=",0 if ok else 1);quit(0 if ok else 1)
