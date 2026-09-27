extends RefCounted
const Forest=preload("res://addons/vegetation/forest.gd")
func run(host: Node)->Dictionary:
	host.view.render_target_update_mode=SubViewport.UPDATE_DISABLED
	var viewport: SubViewport=SubViewport.new();viewport.size=Vector2i(192,192);viewport.own_world_3d=true;viewport.msaa_3d=Viewport.MSAA_2X;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;host.add_child(viewport)
	var env: WorldEnvironment=WorldEnvironment.new();env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color.BLACK;env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=0.8;viewport.add_child(env)
	var light: DirectionalLight3D=DirectionalLight3D.new();light.rotation_degrees=Vector3(-52,-32,0);viewport.add_child(light)
	var camera: Camera3D=Camera3D.new();camera.current=true;camera.fov=65;camera.near=0.12;viewport.add_child(camera)
	var projection: float=96.0/tan(deg_to_rad(32.5))
	var groups: Array=[];var all_ok: bool=true
	for group in ["source_middle","middle_far"]:
		var reference_images: Array[Image]=[];var reference_states: Array[String]=[];var pairs: Array=[]
		for candidate in [false,true]:
			if not host.asset.set_compact_materials(candidate):return {"all_passed":false,"error":"material path"}
			var f=Forest.new();viewport.add_child(f);f.setup(host.asset.meshes,2200);f.visibility(true,false)
			var transforms: Array[Transform3D]=[Transform3D.IDENTITY]
			f.upsert_chunk("single",PackedInt64Array([123]),transforms)
			var initial_pixels: float=300.0 if group=="source_middle" else 120.0
			var final_pixels: float=165.0 if group=="source_middle" else 60.0
			f.reset_lod_state(Vector3(0,9.23563575,18.4712715*projection/initial_pixels),projection,0.0)
			camera.position=Vector3(0,9.23563575,18.4712715*projection/final_pixels)
			f.tick(camera.position,projection,0.5)
			for step in range(11):
				var t: float=0.5+float(step)*0.028
				f.tick(camera.position,projection,t)
				host.asset.uniforms(camera.position,light.global_basis.z.normalized(),t,0.0,2200.0,true)
				await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
				var img: Image=viewport.get_texture().get_image();img.convert(Image.FORMAT_RGB8)
				if not candidate:
					reference_images.append(img);reference_states.append(f.state_sha256())
				else:
					var metrics: Dictionary=reference_images[step].compute_image_metrics(img,false)
					var data: PackedByteArray=img.get_data();var refdata: PackedByteArray=reference_images[step].get_data()
					var mask_differences: int=0
					for k in range(0,data.size(),3):
						var on_a: bool=maxi(data[k],maxi(data[k+1],data[k+2]))>2
						var on_b: bool=maxi(refdata[k],maxi(refdata[k+1],refdata[k+2]))>2
						if on_a!=on_b:mask_differences+=1
					var state_equal: bool=reference_states[step]==f.state_sha256()
					var ok: bool=state_equal and mask_differences==0 and float(metrics["max"])<=8.0
					all_ok=all_ok and ok
					pairs.append({"step":step,"state_equal":state_equal,"coverage_mask_differences":mask_differences,"metrics":metrics,"pass":ok,"active_transitions":f.stats.transitions})
			f.queue_free();await host.get_tree().process_frame
		groups.append({"name":group,"frames":pairs})
	host.asset.set_compact_materials(true)
	viewport.queue_free();await host.get_tree().process_frame
	return {"all_passed":all_ok,"renderer":RenderingServer.get_current_rendering_method(),"device":RenderingServer.get_video_adapter_name(),"size":[192,192],"groups":groups,"scope":"22 paired RC4/RC6 rendered frames across two actual source/middle/far transitions; source appearance across every camera and hardware performance are not certified."}
