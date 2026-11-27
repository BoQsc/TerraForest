# SPDX-License-Identifier: 0BSD
extends "res://tests/vegetation_stability.gd"
# Read-only source-world diagnostic. No persisted graphics/material changes.
var saved_camera := Transform3D.IDENTITY
var evidence_bytes := 0
var region := Rect2i(420, 340, 960, 384)
var motion_region := Rect2i(1160, 500, 640, 160)
var report: Dictionary = {}
var attribution_only := false
var filtered := false
var early := false
var single := false
var shader_only := false
var filtered_attribution := false
var parity_only := false
var current_mode := ""
var filter_material: ShaderMaterial
var filter_mesh: ArrayMesh
var filter_saved := {}
var filter_active := false
const Filter = preload("res://tests/fixtures/grass_filtered.gd")
func retains_runtime_far_filter() -> bool: return true

func pose(frame: int) -> void:
	camera.global_transform = saved_camera
	camera.global_position += saved_camera.basis.x * frame * 0.025
	sync_materials(frame)

func sync_materials(frame: int) -> void:
	if game: game.ground_cover.batches[2].update_surface_lod()
	for material in materials:
		material.set_shader_parameter("cover_eye", camera.global_position)
		material.set_shader_parameter("comparison_time", frame / 60.0)
	if filter_material:
		filter_material.set_shader_parameter("cover_eye",camera.global_position)
		filter_material.set_shader_parameter("comparison_time",frame/60.0)
		filter_material.set_shader_parameter("cover_clock",1000000.0)

func save_bytes(name: String, data: PackedByteArray) -> void:
	evidence_bytes += data.size()
	if not check(evidence_bytes <= (8 if parity_only else 16) * 1024 * 1024, "bounded attribution and motion capture"):
		quit(1); return
	FileAccess.open(output.path_join(name), FileAccess.WRITE).store_buffer(data)

func aa(mode: String) -> void:
	if filtered and current_mode != mode:
		if mode == "filtered": filter_material = Filter.install(filter_mesh,filter_saved,early,single)
		else: Filter.restore(filter_mesh,filter_saved); filter_material = null
		filter_active = mode == "filtered"
		if mode == "early_opaque":
			filter_mesh.clear_surfaces()
			filter_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,filter_saved.arrays,[],{0.02:filter_saved.lods[0.02],preload("res://addons/world_ecosystem/filtered_grass.gd").FAR_ERROR:filter_saved.lods[0.12],0.10:filter_saved.lods[0.2]})
			filter_mesh.surface_set_material(0,filter_saved.material)
			filter_mesh.shadow_mesh=filter_saved.shadow
		current_mode = mode
		if game: preload("res://addons/world_ecosystem/filtered_grass.gd").configure_batch(game.ground_cover.batches[2],filter_mesh,mode=="filtered")
	root.use_taa = mode.begins_with("taa_")
	root.msaa_3d = Viewport.MSAA_DISABLED if mode == "taa_only" else Viewport.MSAA_2X

func compare(_label: String) -> void:
	# The parent finds natural roots but has not moved the loaded player camera.
	var near_eye := base_eye
	saved_camera = camera.global_transform
	base_eye = saved_camera.origin
	var original_aa := root.msaa_3d; var original_taa := root.use_taa
	var original_shaders: Array[Shader] = []
	for material in materials: original_shaders.append(material.shader)
	var source := comparison_shader(AFTER)
	var cover: Node = game.ground_cover
	filter_mesh = cover.preview_meshes[2]
	check(filter_mesh.get_surface_count()==2,"normal source loader enables separate filtered far surface")
	var runtime_far: ShaderMaterial = filter_mesh.surface_get_material(1)
	check(float(runtime_far.get_shader_parameter("cover_clock"))>0.0,"normal source updates far appearance clock")
	check((runtime_far.get_shader_parameter("cover_eye") as Vector3).distance_to(camera.global_position)<1.0,"normal source updates far camera uniform")
	await settle(4)
	save_bytes("source_enabled.png",root.get_texture().get_image().save_png_to_buffer())
	filter_saved = Filter.capture(filter_mesh)
	var species_materials: Array[ShaderMaterial] = []
	for mesh: Mesh in cover.preview_meshes: species_materials.append(mesh.surface_get_material(0))
	check(species_materials.size() == 9, "all nine ground-cover species available for attribution")
	var hidden := Shader.new()
	hidden.code = "shader_type spatial; render_mode cull_disabled; void fragment(){discard;}"
	aa("filtered" if filtered_attribution else "baseline"); apply_shader(source); pose(0); await settle(60)
	var initial := root.get_texture().get_image()
	check(initial.get_size() == Vector2i(1920,1080), "native 1080p source viewport")
	save_bytes("saved_view.png", initial.save_png_to_buffer())
	var variants := ["baseline", "no_specular", "no_backlight", "no_white_flowers", "no_colored_flowers", "no_stones", "no_grass", "no_cover", "no_texture"]
	if filtered: variants = ["baseline"]
	if filtered_attribution: variants=["baseline","no_grass","no_opaque_grass","no_filtered_grass","no_ferns","no_bushes","no_stones","no_white_flowers","no_colored_flowers","no_twigs","no_cover"]
	var far_shader: Shader=filter_material.shader if filter_material else null
	for variant: String in variants:
		apply_shader(source); pose(0)
		if filtered_attribution:filter_material.shader=far_shader
		if variant in ["no_specular", "no_backlight"]:
			var shader := Shader.new()
			var ending := source.code.rfind("}")
			shader.code = source.code.substr(0,ending) + ("SPECULAR=0.0;" if variant == "no_specular" else "BACKLIGHT=vec3(0.0);") + "\n}"
			apply_shader(shader)
		if variant == "no_white_flowers": species_materials[3].shader = hidden
		if variant == "no_colored_flowers":
			species_materials[4].shader = hidden; species_materials[5].shader = hidden
		if variant == "no_stones": species_materials[0].shader = hidden
		if variant == "no_ferns": species_materials[1].shader = hidden
		if variant == "no_bushes":
			species_materials[6].shader=hidden;species_materials[8].shader=hidden
		if variant == "no_twigs":species_materials[7].shader=hidden
		if variant == "no_grass":
			species_materials[2].shader = hidden
			if filtered_attribution:filter_material.shader=hidden
		if variant == "no_opaque_grass":species_materials[2].shader=hidden
		if variant == "no_filtered_grass":filter_material.shader=hidden
		if variant == "no_texture": species_materials[2].set_shader_parameter("grass_detail_strength", 0.0)
		if variant == "no_cover":
			for material in materials: material.shader = hidden
			if filtered_attribution:filter_material.shader=hidden
		await settle(8)
		save_bytes("attribution_"+variant+".png", root.get_texture().get_image().get_region(region).save_png_to_buffer())
		Asset.set_grass_detail(species_materials[2], true)
	apply_shader(source)
	if filtered_attribution:filter_material.shader=far_shader
	pose(0); await settle(8)
	check(initial.get_region(region).get_data() == root.get_texture().get_image().get_region(region).get_data(), "attribution baseline repeats exactly after shader restoration")
	var timing_rows: Array = []
	if not attribution_only:
		if filtered:
			if not single:
				aa("filtered");apply_shader(source)
				var surfaces := preload("res://addons/world_ecosystem/filtered_grass.gd")
				for sample in [[75.0,0],[75.0,48],[35.0,16]]:
					camera.fov=sample[0];pose(sample[1])
					surfaces.configure_batch(cover.batches[2],filter_mesh,false);await settle(8)
					var reference := root.get_texture().get_image()
					# HUD text can vary by one output level even on repeated untouched
					# frames. Compare the 3D field, excluding the top HUD and tool belt.
					var scene_region := Rect2i(0,320,1920,580)
					var expected := reference.get_region(scene_region).get_data()
					await settle(8)
					check(expected==root.get_texture().get_image().get_region(scene_region).get_data(),"unoptimized scene reference repeats fov=%s"%sample[0])
					surfaces.configure_batch(cover.batches[2],filter_mesh);await settle(8)
					var actual := root.get_texture().get_image()
					var identical := expected==actual.get_region(scene_region).get_data()
					check(identical,"populated 3D field unchanged by surface removal fov=%s frame=%s"%sample)
					if not identical:
						var data := actual.get_region(scene_region).get_data();var changed := 0;var maximum := 0;var first := -1
						for byte in expected.size():
							var difference := absi(int(data[byte])-int(expected[byte]))
							if difference>0:
								changed+=1;maximum=maxi(maximum,difference)
								if first<0:first=byte
						print("SURFACE_DIFFERENCE bytes=",changed," maximum=",maximum," first_byte=",first," format=",reference.get_format())
						save_bytes("surface_before.jpg",reference.save_jpg_to_buffer(0.95));save_bytes("surface_after.jpg",actual.save_jpg_to_buffer(0.95))
				camera.fov=75.0
			var original_camera := saved_camera
			camera.global_position = near_eye+Vector3(0,0,0.8)
			camera.look_at(near_eye-Vector3(0,1.65,0))
			saved_camera = camera.global_transform
			var near_pixels := PackedByteArray()
			for mode: String in ["baseline","filtered"]:
				aa(mode); pose(0); await settle(8)
				var near_image := root.get_texture().get_image()
				save_bytes("near_"+mode+".png",near_image.get_region(Rect2i(800,400,320,320)).save_png_to_buffer())
				if mode == "baseline": near_pixels=near_image.get_data()
				else: check(near_pixels == near_image.get_data(),"near view including grass and lighting is byte-identical")
			saved_camera = original_camera
		if parity_only:
			aa("baseline");root.use_taa=original_taa;root.msaa_3d=original_aa
			for index in materials.size():materials[index].shader=original_shaders[index]
			camera.global_transform=saved_camera
			report["world"]={"surface_parity_only":true,"camera":str(saved_camera)}
			return
		var capture_modes := (["baseline", "early_opaque", "filtered"] if early else ["baseline", "filtered"]) if filtered else ["baseline", "taa_msaa", "taa_only"]
		for mode: String in capture_modes:
			aa(mode); pose(0); await settle(90)
			save_bytes(mode+"_still.png", root.get_texture().get_image().get_region(region).save_png_to_buffer())
			var packet := StreamPeerBuffer.new(); packet.put_u32(32)
			# Every rendered frame advances the camera, including non-captured frames.
			for frame in 64:
				pose(frame+1); await settle(1)
				if frame % 2 == 1:
					var data := root.get_texture().get_image().get_region(motion_region).save_webp_to_buffer(true)
					packet.put_u32(data.size()); packet.put_data(data)
			save_bytes(mode+".frames", packet.data_array)
			save_bytes(mode+"_end.png", root.get_texture().get_image().get_region(region).save_png_to_buffer())
			camera.global_transform = saved_camera
		if early and not single:
			for mode: String in ["baseline","filtered"]:
				aa(mode);pose(0);await settle(30)
				var packet := StreamPeerBuffer.new();packet.put_u32(32)
				for frame in 256:
					camera.global_transform=saved_camera
					camera.global_position-=saved_camera.basis.z*frame*0.10
					camera.global_basis=Basis(Vector3.UP,0.20*sin(frame/255.0*PI))*saved_camera.basis
					sync_materials(frame);await settle(1)
					if frame%8==7:
						var data := root.get_texture().get_image().get_region(motion_region).save_webp_to_buffer(true)
						packet.put_u32(data.size());packet.put_data(data)
				save_bytes(mode+"_route.frames",packet.data_array)
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
		# Interleaved order; no readbacks, image encoding or analysis inside timing.
		for group in 6:
			var modes := ["baseline", "taa_msaa", "taa_only"] if group % 2 == 0 else ["taa_only", "taa_msaa", "baseline"]
			if filtered: modes = ["baseline","filtered"] if group % 2 == 0 else ["filtered","baseline"]
			if early: modes = ["baseline","early_opaque","filtered"] if group % 2 == 0 else ["filtered","early_opaque","baseline"]
			for mode: String in modes:
				aa(mode); pose(0); await settle(90)
				var gpu: Array = []; var cpu: Array = []; var frame_times: Array = []; var draws: Array = []; var memory: Array = []
				var previous := Time.get_ticks_usec()
				for frame in 64:
					pose(frame+1); await settle(1)
					var now := Time.get_ticks_usec(); frame_times.append((now-previous)/1000.0); previous = now
					gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
					cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
					draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
					memory.append(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
				timing_rows.append({"group": group, "mode": mode, "gpu_ms": gpu, "cpu_ms": cpu, "frame_ms": frame_times, "draw_calls": draws, "video_memory": memory})
	aa("baseline")
	root.use_taa = original_taa; root.msaa_3d = original_aa
	for index in materials.size(): materials[index].shader = original_shaders[index]
	camera.global_transform = saved_camera
	report["world"] = {"camera": str(saved_camera), "region": str(region), "motion_region": str(motion_region), "original_msaa": original_aa, "original_taa": original_taa, "timings": timing_rows, "filtered_trial": filtered, "early_lods": early, "scope": "Loaded source player camera retained; read-only world. One-at-a-time material/species removal identifies white pixels. Matched 1.6m continuous camera travel with deterministic wind, 32 lossless frames. GPU timings exclude capture/analysis and interleave modes. Modes are paired diagnostic overrides; normal source startup is captured before overrides. Surface-removal parity is checked separately."}

func run() -> void:
	var slot := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="): output = argument.trim_prefix("--check-evidence-dir=")
		if argument.begins_with("--stability-source-slot="): slot = argument.trim_prefix("--stability-source-slot=")
		if argument == "--attribution-only": attribution_only = true
		if argument == "--filtered": filtered = true
		if argument == "--early": early = true; filtered = true
		if argument == "--single": single = true; early = true; filtered = true
		if argument == "--shader-only": shader_only = true
		if argument == "--filtered-attribution":filtered_attribution=true;attribution_only=true;filtered=true;early=true
		if argument == "--surface-parity-only":parity_only=true;filtered=true;early=true
	if output.is_empty() or (slot.is_empty() and not shader_only): push_error("Use admitted runner and existing --stability-source-slot"); quit(1); return
	Engine.max_fps = 60
	report["shader_sha256"] = FileAccess.get_sha256(AFTER)
	report["single_surface"] = single
	report["filtered_attribution"] = filtered_attribution
	report["mesh_sha256"] = FileAccess.get_sha256("res://addons/world_ecosystem/woodland_mesh.gd")
	for resource_path in ["res://tests/fixtures/grass_filtered.gd", "res://tests/fixtures/grass_filtered.gdshader", "res://addons/world_ecosystem/filtered_grass.gd", "res://addons/world_ecosystem/filtered_grass.gdshader"]:
		report[resource_path+"_sha256"] = FileAccess.get_sha256(resource_path)
		FileAccess.open(output.path_join(resource_path.get_file()),FileAccess.WRITE).store_string(FileAccess.get_file_as_string(resource_path))
	FileAccess.open(output.path_join("driver.gd"),FileAccess.WRITE).store_string(FileAccess.get_file_as_string("res://tests/vegetation_reconstruction.gd"))
	if shader_only:
		world=Node3D.new();root.add_child(world)
		camera=Camera3D.new();world.add_child(camera);camera.position=Vector3(0,1,2);camera.look_at(Vector3.ZERO);camera.current=true
		var view := MeshInstance3D.new();view.mesh=Asset.build(2);world.add_child(view)
		var saved := Filter.capture(view.mesh);saved.material.shader=comparison_shader(AFTER)
		Asset.set_grass_detail(saved.material,true)
		var material := Filter.install(view.mesh,saved,true,single)
		material.set_shader_parameter("cover_eye",camera.position)
		await settle(16)
		check(view.mesh.get_surface_count()==(1 if single else 2),"expected grass surfaces submitted to renderer")
		if not single:
			view.visible=false
			var batch: Node3D=ClassDB.instantiate("NativeStaticBatch");world.add_child(batch)
			check(batch.configure_asset("grass/surface-check",view.mesh),"surface test native asset accepted")
			check(batch.configure_render_streaming(true,2048,16,1048576,2,65536),"surface test native streaming configured")
			check(batch.upsert_transforms(PackedInt64Array([1]),[Transform3D.IDENTITY]),"surface test instance admitted")
			batch.set_casts_shadows(false)
			await settle(4)
			var surface := preload("res://addons/world_ecosystem/filtered_grass.gd")
			var near_cases := 0;var far_cases := 0
			for fov: float in [35.0,75.0,100.0]:
				camera.fov=fov
				for distance: float in [2.0,20.0,40.0,70.0,120.0]:
					camera.position=Vector3(0,0.4,distance);camera.look_at(Vector3(0,0.3,0))
					surface.configure_batch(batch,view.mesh,false);await settle(4)
					var expected := root.get_texture().get_image().get_data()
					check(surface.configure_batch(batch,view.mesh),"surface optimization accepted")
					await settle(4)
					for child in batch.get_children():
						if child is MultiMeshInstance3D and child.visible:
							if child.multimesh.mesh==view.mesh.get_meta("surface_lod_near"):near_cases+=1
							if child.multimesh.mesh==view.mesh.get_meta("surface_lod_far"):far_cases+=1
					check(expected==root.get_texture().get_image().get_data(),"surface parity fov=%s distance=%s"%[fov,distance])
			check(near_cases>0 and far_cases>0,"both single-surface paths actually rendered")
		world.free();await process_frame
	else: await actual_world(slot)
	report.merge({"checks": checks, "failures": failures, "world_input": results.get("world_input",{}), "evidence_bytes": evidence_bytes, "test_modified_source": false, "runtime_far_filter_enabled": true})
	FileAccess.open(output.path_join("vegetation_reconstruction.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	for resource_path in ["res://tests/vegetation_reconstruction.gd", "res://tests/fixtures/grass_filtered.gd", "res://tests/fixtures/grass_filtered.gdshader", "res://addons/world_ecosystem/filtered_grass.gd", "res://addons/world_ecosystem/filtered_grass.gdshader"]:
		if not FileAccess.file_exists(resource_path+".uid"):
			FileAccess.open(resource_path+".uid",FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	print("VEGETATION_RECONSTRUCTION failures=",failures)
	quit(1 if failures else 0)
