# SPDX-License-Identifier: 0BSD
extends SceneTree

var failures:=0
func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->void:
	print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
func run()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	var effects=load("res://addons/impact_effects/impact_effects.gd").new()
	effects.settings_path="";root.add_child(effects)
	for style:int in [0,1,0]:
		effects.set_style(style,false)
		var started:=Time.get_ticks_usec()
		effects.prepare_resources()
		print("IMPACT_PREPARE style=",style," us=",Time.get_ticks_usec()-started)
		var before:Dictionary=effects.meshes.duplicate()
		var event_count:int=effects.emitted_events
		var template_tint:=Vector4(.1,.2,.3,.4)
		effects.motions.fragments.set_shader_parameter("tint",template_tint)
		effects.prepare_resources()
		check(effects.meshes==before and effects.pool.is_empty() and effects.emitted_events==event_count,"preparation reuses resources without emitting or allocating particles")
		check(effects.motions.size()==2 and effects.meshes.size()==(6 if style==0 else 4),"both motion shaders and selected-style meshes are prepared")
		for material:String in ["soil","stone","wood","metal","flesh"]:
			started=Time.get_ticks_usec()
			check(effects.burst(Vector3.ZERO,Vector3.UP,material),"prepared burst "+material)
			print("IMPACT_BURST style=",style," material=",material," us=",Time.get_ticks_usec()-started)
		check(effects.meshes==before,"first bursts create no additional meshes")
		check(effects.pool[0].process_material!=effects.pool[1].process_material,"emitters retain independent motion uniforms")
		check(effects.motions.fragments.get_shader_parameter("tint")==template_tint,"burst tint does not mutate the cached template")
		effects.set_enabled(false,false)
		check(effects.pool.is_empty() and not effects.burst(Vector3.ZERO,Vector3.UP,"stone"),"disabled effects clear emitters and refuse bursts")
		effects.set_enabled(true,false)
		await process_frame
	effects.free();await process_frame;await process_frame
	check(Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"test never captures the pointer")
	print("IMPACT_RESOURCES failures=",failures);quit(1 if failures else 0)
