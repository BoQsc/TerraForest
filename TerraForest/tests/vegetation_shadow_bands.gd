# SPDX-License-Identifier: 0BSD
extends "res://tests/vegetation_stability.gd"
# A source-world counterfactual for near-ground bands. No production overrides
# survive the test. Camera motion, time and population are identical in each case.
var source_codes:Dictionary={}
var cover_materials:Array[ShaderMaterial]=[]
var lights:Array=[]
var starting_view:Transform3D
var reference:Array=[]
var observations:Array=[]
var written:=0
var band_packets:=StreamPeerBuffer.new()
var modes:=["baseline","current","proxy_off","all_shadows_off","repeat"]
var corrected:Array=[]

func retains_runtime_far_filter() -> bool:return true

func capture_file(name:String,data:PackedByteArray) -> void:
	written+=data.size()
	if written>2560*1024:check(false,"bounded shadow-band evidence");quit(1);return
	FileAccess.open(output.path_join(name),FileAccess.WRITE).store_buffer(data)

func select_case(mode:String) -> void:
	for light in lights:light[0].shadow_enabled=false if mode=="all_shadows_off" else light[1]
	for owner in game.ground_cover.batches:owner.set_casts_shadows(mode!="cover_shadows_off")
	for mat in cover_materials:
		var code:String=source_codes[mat]
		code=code.replace("shader_type spatial;","shader_type spatial;\nuniform float fixed_time=0.0;").replace("TIME","fixed_time")
		if mode in ["baseline","repeat"]:
			code=code.replace("proxy_triangle_in_view(ca,cb,cc)","true").replace("proxy_stone_in_view(center)","true")
		if mode=="proxy_off" and (code.contains("varying flat vec2 center_px") or code.contains("stone_view_basis")):
			code=code.replace("void fragment() {", "void fragment() { discard;").replace("void fragment(){", "void fragment(){ discard;")
		var program:=Shader.new();program.code=code;mat.shader=program
		mat.set_shader_parameter("fixed_time",0.0);mat.set_shader_parameter("cover_clock",1000000.0)

func band_pose(frame:int) -> void:
	var local_frame:=frame%24
	camera.global_transform=starting_view
	if frame>=24:camera.global_position+=starting_view.basis.x*(local_frame*.025)-starting_view.basis.z*(local_frame*.07)
	for mat in cover_materials:
		mat.set_shader_parameter("cover_eye",camera.global_position)
		mat.set_shader_parameter("fixed_time",local_frame*.2)
	for owner in game.ground_cover.batches:owner.update_surface_lod()

func compare(_label:String) -> void:
	Engine.time_scale=0.0
	starting_view=camera.global_transform
	for light in game.find_children("*","DirectionalLight3D",true,false):lights.append([light,light.shadow_enabled])
	check(not lights.is_empty(),"normal directional light found")
	for mat:ShaderMaterial in game.ground_cover.foliage_materials:
		cover_materials.append(mat);source_codes[mat]=mat.shader.code
	for mode in modes:
		select_case(mode);band_pose(0);await settle(24)
		for frame in 48:
			band_pose(frame);await settle(2)
			var image:=root.get_texture().get_image();image.convert(Image.FORMAT_RGB8)
			var region:=image.get_region(Rect2i(200,480,1520,400))
			var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(region.get_data());var digest:=hash.finish().hex_encode()
			var small:Image=region.duplicate();small.resize(190,50,Image.INTERPOLATE_BILINEAR);small.convert(Image.FORMAT_L8)
			var tiny:Image=small.duplicate();tiny.resize(95,25,Image.INTERPOLATE_BILINEAR)
			var metadata:=JSON.stringify({"case":mode,"frame":frame,"width":95,"height":25,"native_near_sha256":digest}).to_utf8_buffer()
			band_packets.put_u32(metadata.size());band_packets.put_data(metadata);band_packets.put_u32(tiny.get_data().size());band_packets.put_data(tiny.get_data())
			var bytes:=small.get_data();var difference:=0.0;var peak:=0;var changed:=0;var row_deltas:Array=[]
			if mode=="baseline":reference.append({"sha256":digest,"luma":bytes})
			var ref:PackedByteArray=reference[frame].luma
			for y in 50:
				var row_delta:=0.0
				for x in 190:
					var delta:int=int(bytes[y*190+x])-int(ref[y*190+x]);difference+=abs(delta);peak=maxi(peak,abs(delta));changed+=int(abs(delta)>4);row_delta+=delta
				row_deltas.append(row_delta/190.0)
			observations.append({"case":mode,"frame":frame,"near_sha256":digest,"mean_abs_luma_bytes":difference/bytes.size(),"peak_luma_bytes":peak,"changed_over_4":changed,"row_signed_luma_bytes":row_deltas,"camera":str(camera.global_transform)})
			if mode=="current":corrected.append(digest)
			if mode=="proxy_off":check(digest==corrected[frame],"corrected nearby geometry and brightness exactly match proxy-free foreground "+str(frame))
			if mode=="repeat":check(digest==reference[frame].sha256,"exact repeated faulty view "+str(frame))
			if frame in [6,30]:
				var preview:Image=image.duplicate();preview.resize(480,270,Image.INTERPOLATE_LANCZOS)
				capture_file(mode+"_"+str(frame)+".jpg",preview.save_jpg_to_buffer(.60))
			if frame==30 and mode in ["baseline","current","proxy_off"]:capture_file(mode+"_near.png",image.get_region(Rect2i(512,576,512,192)).save_png_to_buffer())
	var faulty_frames:=0
	for frame in 48:faulty_frames+=int(reference[frame].sha256!=corrected[frame])
	check(faulty_frames>24,"faulty baseline reproduces foreground contamination across stationary wind and movement")
	check(faulty_frames<48,"clean baseline frames retain exact nearby brightness and vegetation")
	results["faulty_foreground_frames"]=faulty_frames
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var costs:Array=[]
	for mode in ["baseline","current"]:
		select_case(mode);band_pose(6);await settle(90)
	for cycle in 4:
		for mode in ["baseline","current","current","baseline"]:
			select_case(mode);band_pose(6);await settle(6)
			var gpu:Array=[]
			for frame in 24:
				await RenderingServer.frame_post_draw
				gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			gpu.sort()
			costs.append({"case":mode,"cycle":cycle,"gpu_p50_ms":gpu[12],"gpu_p95_ms":gpu[22],"draws":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)})
	results["paired_gpu_cost"]=costs
	# Restore shared materials and native policy before inherited population checks.
	for mat in cover_materials:
		var program:=Shader.new();program.code=source_codes[mat];mat.shader=program
	for owner in game.ground_cover.batches:owner.set_casts_shadows(true)
	for light in lights:light[0].shadow_enabled=light[1]
	camera.global_transform=starting_view;Engine.time_scale=1.0

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="):output=arg.trim_prefix("--check-evidence-dir=")
	if output.is_empty():quit(1);return
	Engine.max_fps=60
	await actual_world("Homestead_Valley")
	results.merge({"checks":checks,"failures":failures,"rows":observations,"scope":"Existing saved source pose, stationary animated wind then matched moving poses; production projection guard versus disabled guard, proxy removal and global shadow controls; paired GPU samples exclude image readback. Near-ground hashes are native resolution; luma statistics are reduced 8x and are diagnostic, not visual acceptance."})
	for name in ["proxy_projection.gdshaderinc","filtered_grass.gdshader","filtered_fern.gdshader","filtered_stone.gdshader"]:
		capture_file(name,FileAccess.get_file_as_bytes("res://addons/world_ecosystem/"+name))
	if not FileAccess.file_exists("res://addons/world_ecosystem/proxy_projection.gdshaderinc.uid"):FileAccess.open("res://addons/world_ecosystem/proxy_projection.gdshaderinc.uid",FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	capture_file("near_motion.frames",band_packets.data_array)
	capture_file("shadow_bands.json",JSON.stringify(results).to_utf8_buffer())
	capture_file("vegetation_shadow_bands.gd",FileAccess.get_file_as_bytes("res://tests/vegetation_shadow_bands.gd"))
	if not FileAccess.file_exists("res://tests/vegetation_shadow_bands.gd.uid"):FileAccess.open("res://tests/vegetation_shadow_bands.gd.uid",FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	print("VEGETATION_SHADOW_BANDS failures=",failures);quit(1 if failures else 0)
