extends SceneTree
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	var folder:="res://reports/blood_effects/visual"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--effects-evidence="):folder=argument.trim_prefix("--effects-evidence=")
	DirAccess.make_dir_recursive_absolute(folder)
	var scene:=Node3D.new();root.add_child(scene)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("394048")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7;scene.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-45,-30,0);sun.light_energy=1.5;scene.add_child(sun)
	var zombie=load("res://addons/characters/runtime/zombie.gd").new();scene.add_child(zombie)
	zombie.set_behavior(false);zombie.set_physics_process(false);zombie.animation_player.pause()
	var camera:=Camera3D.new();scene.add_child(camera);camera.position=Vector3(0,1.3,2.5);camera.look_at(Vector3(0,1.1,0));camera.make_current()
	var effects=load("res://addons/impact_effects/impact_effects.gd").new();effects.settings_path="";scene.add_child(effects)
	await process_frame;await process_frame
	check(effects.material_for({"kind":"zombie"})=="flesh","zombie bodies classify as flesh")
	check(effects.material_for({"kind":"model","impact_material":"flesh","material":"other"})=="flesh","explicit flesh marker does not require changing damage material")
	check(effects.material_for({"kind":"object","material":"flesh"})=="flesh","external flesh contact adapters are supported")
	check(effects.material_for({"kind":"actor","material":"other"}).is_empty(),"unknown actors do not automatically bleed")
	check(effects.material_for({"kind":"vehicle"})=="metal" and effects.material_for({"kind":"tree"})=="wood","nonflesh material routing is unchanged")
	check(not effects.burst(Vector3.INF,Vector3.UP,"flesh") and not effects.burst(Vector3.ZERO,Vector3.ZERO,"flesh"),"invalid contacts cannot allocate emitters")
	effects.contact({"kind":"zombie"})
	effects.contact({"kind":"model","impact_material":"flesh","repairing":true,"position":Vector3.ZERO,"normal":Vector3.UP})
	check(effects.emitted_events==0 and effects.pool.is_empty(),"missing pose and repair contacts do not bleed")
	var point:=Vector3(0,1.25,.16)
	for appearance in 2:
		effects.set_style(appearance,false)
		for material in ["stone","flesh","metal","flesh"]:
			check(effects.burst(point,Vector3.BACK,material),"pooled emitter accepts "+material+" in style "+str(appearance))
			check(effects.pool.size()==1,"successive material changes reuse the existing emitter")
			if material=="flesh":check(effects.pool[0].draw_passes==1 and effects.pool[0].draw_pass_1==effects.meshes.blood and effects.last_event.count==23,"blood replaces debris and dust without extra particle slots")
			await create_timer(1.3).timeout
			check(effects.statistics().active==0,"transient "+material+" particles retire")
	effects.set_style(0,false)
	effects.burst(point,Vector3.BACK,"flesh");await create_timer(1.3).timeout
	await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join("before.png"))
	effects.burst(point,Vector3.BACK,"flesh")
	var previous:=0.0
	for time in [.04,.10,.18,.30,.50,.85]:
		await create_timer(time-previous).timeout;previous=time
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(folder.path_join("blood_%03d.png"%int(time*1000)))
	check(effects.statistics().active==0,"blood has fully expired within one second")
	for burst_index in effects.POOL_LIMIT:check(effects.burst(point,Vector3.BACK,"flesh"),"shared pool accepts burst "+str(burst_index))
	check(not effects.burst(point,Vector3.BACK,"flesh") and effects.statistics().particle_capacity==384,"blood shares the existing 384-slot hard limit")
	effects.set_enabled(false,false)
	check(effects.pool.is_empty() and not effects.burst(point,Vector3.BACK,"flesh"),"master toggle immediately clears and suppresses blood")
	scene.free();await process_frame;await process_frame
	print("BLOOD_EFFECTS checks=",checks," failures=",failures);quit(1 if failures else 0)
