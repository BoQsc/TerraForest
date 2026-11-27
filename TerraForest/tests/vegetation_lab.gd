# SPDX-License-Identifier: 0BSD
extends "res://tests/vegetation_stability.gd"
# In-memory experiments only. Production files are hashed before/after; the
# inherited loader preserves the source save, population and instance buffers.
const PlanPath = "res://tests/fixtures/vegetation_lab.json"
const Filter = preload("res://tests/fixtures/grass_filtered.gd")
const Surface = preload("res://addons/world_ecosystem/filtered_grass.gd")
const FernFilter = preload("res://tests/fixtures/fern_filtered.gd")
const RuntimeDetail = preload("res://addons/world_ecosystem/filtered_detail.gd")
const Detail = preload("res://tests/fixtures/detail_speckles.gd")
var plan: Dictionary
var configurations := {}
var requested: PackedStringArray = []
var grass: ArrayMesh
var original_grass := {}
var source_materials: Array[ShaderMaterial] = []
var authored_shader: Shader
var far_material: ShaderMaterial
var fern_mesh: ArrayMesh
var original_fern := {}
var fern_far_material: ShaderMaterial
var fern_roots: Array[Vector3] = []
var fern_bases: Array[Basis] = []
var fern_anchors: Array[Vector3] = []
var camera_start := Transform3D.IDENTITY
var tile := Rect2i(0, 0, 320, 128)
var anchors: Array[Vector3] = []
var lab := {"rows":[], "cost":[], "near_parity":{}, "fixture_valid":false}
var packets := StreamPeerBuffer.new()
var packet_count := 0
var allocated := 0
var budget_failed := false
var original_parameters: Array[Dictionary] = []
var shader_cache := {}
var grounded_view := false
var lab_interleaved_cost := ""
var lab_visual_only := false
var source_cost := false
var lab_cost_only := false
var wait_idle := false
var motion_cases: PackedStringArray = []
var detail_original := {}
var detail_anchors := {"stone":[],"flower":[]}
var detail_requested := false
var stone_mean := Vector3.ONE
var detail_kinds: Array[String] = []
var detail_far_materials: Array[ShaderMaterial] = []

func cached_shader(code: String) -> Shader:
	if not shader_cache.has(code):
		var shader := Shader.new();shader.code=code;shader_cache[code]=shader
	return shader_cache[code]

func retains_runtime_far_filter() -> bool: return true

func write_artifact(name: String, data: PackedByteArray) -> void:
	if allocated+data.size()>16*1024*1024:
		if not budget_failed: check(false,"lab evidence exceeds its admitted 16 MiB cap")
		budget_failed=true
		return
	allocated+=data.size()
	FileAccess.open(output.path_join(name),FileAccess.WRITE).store_buffer(data)

func setup_case(id: String) -> void:
	var configuration: Dictionary=configurations[id]
	Surface.configure_batch(game.ground_cover.batches[2],grass,false)
	Filter.restore(grass,original_grass);far_material=null
	Surface.configure_batch(game.ground_cover.batches[1],fern_mesh,false)
	Filter.restore(fern_mesh,original_fern);fern_far_material=null
	detail_far_materials.clear()
	for species: int in detail_original:
		Surface.configure_batch(game.ground_cover.batches[species],game.ground_cover.preview_meshes[species],false)
		Detail.restore(game.ground_cover.preview_meshes[species],detail_original[species])
	for index in source_materials.size():
		var material := source_materials[index]
		material.shader=authored_shader
		for parameter: String in original_parameters[index]:
			material.set_shader_parameter(parameter,original_parameters[index][parameter])
		material.set_shader_parameter("cover_clock",1000000.0)
	var material: ShaderMaterial=original_grass.material
	var arrays: Array=original_grass.arrays.duplicate(true)
	var lods := {0.02:original_grass.lods[0.02],configuration.far_error:original_grass.lods[0.12],configuration.horizon_error:original_grass.lods[0.2]}
	if configuration.fixed_lod!="automatic":
		var selected: PackedInt32Array=original_grass.lods[{"low":0.02,"eight":0.12,"three":0.2}[configuration.fixed_lod]]
		var main_indices := selected.duplicate()
		# Godot requires every LOD index list to be shorter than the base list.
		# One zero-area triangle keeps the same visible geometry and LOD layout.
		main_indices.append_array(PackedInt32Array([selected[0],selected[0],selected[0]]))
		arrays[Mesh.ARRAY_INDEX]=main_indices
		# Keep the LOD count/thresholds for the separate original shadow mesh.
		for error: float in lods:lods[error]=selected
	grass.clear_surfaces();grass.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],lods)
	grass.surface_set_material(0,material);grass.shadow_mesh=original_grass.shadow
	if configuration.coverage=="filtered":
		far_material=Surface.apply(grass,original_grass.arrays,original_grass.lods,material,configuration.far_error,configuration.horizon_error)
		far_material.shader=cached_shader(far_material.shader.code.replace("shader_type spatial;","shader_type spatial;\nuniform float comparison_time=0.0;").replace("TIME","comparison_time"))
		Surface.configure_batch(game.ground_cover.batches[2],grass,configuration.surface_removal)
	var code := authored_shader.code
	var ending := code.rfind("}")
	var tail := ""
	if not configuration.specular:tail+="SPECULAR=0.0;"
	if not configuration.backlight:tail+="BACKLIGHT=vec3(0.0);"
	code=code.substr(0,ending)+tail+"\n}"
	if not configuration.receive_shadows:code=code.replace("diffuse_burley;","diffuse_burley, shadows_disabled;")
	if not configuration.lit:code=code.replace("diffuse_burley;","unshaded;")
	if configuration.normal_mode=="up":code=code.replace("void vertex() {","void vertex() {\nNORMAL=vec3(0.0,1.0,0.0);")
	if not configuration.fade_discard:code=code.replace("if(coverage<=threshold)discard;","")
	material.shader=cached_shader(code)
	if not configuration.wind:material.set_shader_parameter("wind_strength",0.0)
	if not configuration.self_shade:material.set_shader_parameter("distant_self_shade",0.0)
	if not configuration.texture:material.set_shader_parameter("grass_detail_strength",0.0)
	if configuration.fern_coverage:
		fern_far_material=FernFilter.install(fern_mesh,original_fern,configuration.fern_error,configuration.fern_cluster,configuration.fern_shader)
		fern_far_material.shader=cached_shader(fern_far_material.shader.code)
		Surface.configure_batch(game.ground_cover.batches[1],fern_mesh,configuration.fern_removal)
	var detail_probe: String=configuration.get("detail_probe","none")
	if detail_probe!="none":
		for species: int in ([0] if detail_probe.begins_with("stone") else [3,4,5]):
			var detail_material := source_materials[species]
			detail_material.shader=cached_shader(Detail.control_code(authored_shader.code,detail_probe))
			if detail_probe=="stone_flat_color":detail_material.set_shader_parameter("lab_stone_mean",stone_mean)
			if detail_probe.ends_with("fixed_low"):
				var saved: Dictionary=detail_original[species];var detail_arrays: Array=saved.arrays.duplicate()
				var low: PackedInt32Array=saved.lods.values()[0];var main := low.duplicate();main.append_array(PackedInt32Array([low[0],low[0],low[0]]))
				detail_arrays[Mesh.ARRAY_INDEX]=main
				var mesh: ArrayMesh=game.ground_cover.preview_meshes[species]
				mesh.clear_surfaces();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,detail_arrays,[],saved.lods);mesh.surface_set_material(0,detail_material)
		if detail_probe in ["stone_filtered","combined_filtered"]:
			var stone_far := RuntimeDetail.install_stone(game.ground_cover.preview_meshes[0],detail_original[0]) if configuration.get("detail_runtime",false) else Detail.install_stone(game.ground_cover.preview_meshes[0],detail_original[0],configuration.get("stone_lookup",false),configuration.get("stone_early",false));detail_far_materials.append(stone_far)
			stone_far.shader=cached_shader(stone_far.shader.code)
			Surface.configure_batch(game.ground_cover.batches[0],game.ground_cover.preview_meshes[0],true)
		if detail_probe in ["flower_filtered","combined_filtered"]:
			for species in [3,4,5]:
				var flower_far := RuntimeDetail.install_flower(game.ground_cover.preview_meshes[species],detail_original[species]) if configuration.get("detail_runtime",false) else Detail.install_flower(game.ground_cover.preview_meshes[species],detail_original[species],configuration.get("flower_groups",false));detail_far_materials.append(flower_far)
				var flower_code: String=flower_far.shader.code
				if not flower_code.contains("uniform float comparison_time"):flower_code=flower_code.replace("shader_type spatial;","shader_type spatial;\nuniform float comparison_time=0.0;").replace("TIME","comparison_time")
				flower_far.shader=cached_shader(flower_code)
				Surface.configure_batch(game.ground_cover.batches[species],game.ground_cover.preview_meshes[species],true)
	var hidden := cached_shader("shader_type spatial; void fragment(){discard;}")
	for species: int in configuration.hide:source_materials[species].shader=hidden
	if 2 in configuration.hide and far_material:far_material.shader=hidden
	if 1 in configuration.hide and fern_far_material:fern_far_material.shader=hidden
	root.msaa_3d=Viewport.MSAA_8X if configuration.msaa==8 else Viewport.MSAA_2X
	root.use_taa=configuration.taa

func path_transform(path: String, frame: int) -> Transform3D:
	var result := camera_start
	if path=="strafe":result.origin+=camera_start.basis.x*frame*0.025
	if path=="approach_turn":
		result.origin-=camera_start.basis.z*frame*0.10
		result.basis=Basis(Vector3.UP,frame*0.002)*camera_start.basis
	return result

func anchor_stays_visible(point: Vector3) -> bool:
	var visible := true
	for path: String in plan.paths:
		for frame in 32:
			camera.global_transform=path_transform(path,frame)
			var pixel := camera.unproject_position(point)
			if camera.is_position_behind(point) or pixel.x<2 or pixel.x>=1918 or pixel.y<2 or pixel.y>=1078:
				visible=false;break
		if not visible:break
	camera.global_transform=camera_start
	return visible

func luma_at(image: Image, point: Vector2) -> float:
	if not check_sample_bounds(image,point):return 0.0
	return super.luma_at(image,point)

func check_sample_bounds(image: Image, point: Vector2) -> bool:
	if point.is_finite() and point.x>=0 and point.y>=0 and point.x<=image.get_width()-1 and point.y<=image.get_height()-1:return true
	check(false,"temporal anchor left the image; never extrapolate image-edge samples")
	return false

func lab_pose(path: String, frame: int) -> void:
	camera.global_transform=path_transform(path,frame)
	for material in source_materials:
		material.set_shader_parameter("comparison_time",frame/60.0)
		material.set_shader_parameter("cover_eye",camera.global_position)
	if far_material:
		far_material.set_shader_parameter("comparison_time",frame/60.0)
		far_material.set_shader_parameter("cover_eye",camera.global_position)
		far_material.set_shader_parameter("cover_clock",1000000.0)
	if fern_far_material:
		fern_far_material.set_shader_parameter("comparison_time",frame/60.0)
		fern_far_material.set_shader_parameter("cover_eye",camera.global_position)
		fern_far_material.set_shader_parameter("cover_clock",1000000.0)
	game.ground_cover.batches[2].update_surface_lod()
	game.ground_cover.batches[1].update_surface_lod()
	for material in detail_far_materials:
		material.set_shader_parameter("cover_eye",camera.global_position);material.set_shader_parameter("cover_clock",1000000.0)
		material.set_shader_parameter("comparison_time",frame/60.0)
	for species: int in detail_original:game.ground_cover.batches[species].update_surface_lod()

func establish_fern_anchors() -> void:
	setup_case("filtered_optimized");lab_pose("hold",0);await settle(24)
	var present := root.get_texture().get_image()
	var control := authored_shader.code.replace("void vertex() {","varying flat float lab_fern_distance;\nvoid vertex() {\nlab_fern_distance=distance(MODEL_MATRIX[3].xyz,cover_eye);")
	control=control.replace("void fragment() {","void fragment() {\nif(lab_fern_distance>=60.0 && lab_fern_distance<=120.0)discard;")
	source_materials[1].shader=cached_shader(control);await settle(12)
	var removed := root.get_texture().get_image()
	var used_pixels := {};var visible_plants := 0
	var triangles: PackedInt32Array=original_fern.lods[0.08]
	for instance_index in fern_roots.size():
		var root_point := fern_roots[instance_index]
		var distance := root_point.distance_to(camera.global_position)
		if distance<60 or distance>120:continue
		var plant_samples := 0
		for triangle in range(0,triangles.size(),3):
			var local_point: Vector3=(original_fern.arrays[Mesh.ARRAY_VERTEX][triangles[triangle]]+original_fern.arrays[Mesh.ARRAY_VERTEX][triangles[triangle+1]]+original_fern.arrays[Mesh.ARRAY_VERTEX][triangles[triangle+2]])/3.0
			var point: Vector3=root_point+fern_bases[instance_index]*local_point
			var pixel := camera.unproject_position(point);var key := Vector2i(pixel*2.0)
			if used_pixels.has(key) or not tile.has_point(Vector2i(pixel)) or not anchor_stays_visible(point):continue
			if absf(luma_at(present,pixel)-luma_at(removed,pixel))<=0.015:continue
			fern_anchors.append(point);used_pixels[key]=true;plant_samples+=1
			if plant_samples==3 or fern_anchors.size()==32:break
		if plant_samples:visible_plants+=1
		if fern_anchors.size()==32:break
	check(fern_anchors.size()>=12,"fern trial has at least 12 visible distance-isolated anchors throughout motion")
	check(visible_plants>=4,"fern anchors represent at least four distinct plants")
	lab["fern_field"]={"distance_isolated":true,"distance_band_m":[60,120],"plants":visible_plants,"sampling":"Authored far-triangle centroids transformed by actual instance bases; at most three visible samples per plant, half-pixel deduplication.","anchors":fern_anchors.map(func(p:Vector3):return [p.x,p.y,p.z])}
	write_artifact("fern_present.png",present.get_region(tile).save_png_to_buffer())
	write_artifact("fern_removed.png",removed.get_region(tile).save_png_to_buffer())
	setup_case("reference");lab_pose("hold",0);await settle(12)

func establish_field() -> bool:
	setup_case("reference");lab_pose("hold",0);await settle(24)
	var reference := root.get_texture().get_image()
	if not check(reference.get_size()==Vector2i(1920,1080),"lab uses native 1080p source viewport"):return false
	write_artifact("context.jpg",reference.save_jpg_to_buffer(0.92))
	# Removing all grass can expose a far root through foreground grass and falsely
	# label the foreground as distant. Remove only 60-120m instances; foreground
	# depth and lighting stay intact, so changed pixels prove visible far coverage.
	var distance_control := authored_shader.code.replace("void vertex() {", "varying flat float lab_root_distance;\nvoid vertex() {\nlab_root_distance=distance(MODEL_MATRIX[3].xyz,cover_eye);")
	distance_control=distance_control.replace("void fragment() {", "void fragment() {\nif(lab_root_distance>=60.0 && lab_root_distance<=120.0)discard;")
	source_materials[2].shader=cached_shader(distance_control)
	lab_pose("hold",0);await settle(12)
	var without := root.get_texture().get_image()
	var groups := {}
	for point: Vector3 in sample_roots:
		var distance := point.distance_to(camera.global_position)
		if distance<60.0 or distance>120.0 or camera.is_position_behind(point):continue
		var pixel := camera.unproject_position(point+Vector3(0,0.20,0))
		if pixel.x<0 or pixel.x>=1919 or pixel.y<320 or pixel.y>=832:continue
		var cell := Vector2i(int(pixel.x)/320,(int(pixel.y)-320)/128)
		if not groups.has(cell):groups[cell]=[]
		groups[cell].append(point+Vector3(0,0.20,0))
	var best := -1
	var ownership := 0
	for cell: Vector2i in groups:
		if groups[cell].size()<24:continue
		var rectangle := Rect2i(cell.x*320,320+cell.y*128,320,128)
		var visible_anchors: Array[Vector3]=[]
		for point: Vector3 in groups[cell]:
			var pixel := camera.unproject_position(point)
			if absf(luma_at(reference,pixel)-luma_at(without,pixel))>0.02 and anchor_stays_visible(point):visible_anchors.append(point)
			if visible_anchors.size()==48:break
		if visible_anchors.size()<12:continue
		var pixels := 0
		for y in range(rectangle.position.y,rectangle.end.y):
			for x in range(rectangle.position.x,rectangle.end.x):
				if absf(luma_at(reference,Vector2(x,y))-luma_at(without,Vector2(x,y)))>0.04:pixels+=1
		if pixels>best:
			best=pixels;ownership=pixels;tile=rectangle;anchors=visible_anchors
	var valid := check(ownership>=128 and anchors.size()>=12,"far crop has measured grass contribution and visible 60-120m anchors")
	lab["field"]={"rectangle":[tile.position.x,tile.position.y,tile.size.x,tile.size.y],"grass_changed_pixels":ownership,"distance_isolated":true,"distance_band_m":[60.0,120.0],"anchors":anchors.map(func(p:Vector3):return [p.x,p.y,p.z]),"camera":str(camera_start)}
	if valid:
		write_artifact("field.png",reference.get_region(tile).save_png_to_buffer())
		write_artifact("field_no_grass.png",without.get_region(tile).save_png_to_buffer())
	setup_case("reference");lab_pose("hold",0);await settle(12)
	check(reference.get_region(tile).get_data()==root.get_texture().get_image().get_region(tile).get_data(),"untouched baseline repeats after grass removal/restoration")
	return valid and failures==0

func establish_detail_anchors() -> void:
	# Actual transformed mesh centroids, confirmed visible by distant-only removal.
	# Sample across the unobstructed source view, not a crop chosen for grass.
	for kind: String in detail_kinds:
		setup_case("fern_cluster");lab_pose("hold",0);await settle(24)
		var present := root.get_texture().get_image()
		for species: int in ([0] if kind=="stone" else [3,4,5]):source_materials[species].shader=cached_shader(Detail.control_code(authored_shader.code,kind+"_removed"))
		await settle(12);var removed := root.get_texture().get_image()
		var used := {};var plants := 0;var groups := {}
		for owner: Variant in game.ground_cover.resident:
			for species: int in ([0] if kind=="stone" else [3,4,5]):
				var row: Dictionary=game.ground_cover.resident[owner][species];var transforms: PackedFloat32Array=row.transforms
				var saved: Dictionary=detail_original[species];var indices: PackedInt32Array=saved.lods.values()[0]
				for i in row.ids.size():
					var origin := Vector3(transforms[i*12+3],transforms[i*12+7],transforms[i*12+11]);var distance := origin.distance_to(camera_start.origin)
					if distance<60 or distance>120:continue
					var basis := Basis(Vector3(transforms[i*12],transforms[i*12+4],transforms[i*12+8]),Vector3(transforms[i*12+1],transforms[i*12+5],transforms[i*12+9]),Vector3(transforms[i*12+2],transforms[i*12+6],transforms[i*12+10]))
					var samples := 0
					for j in range(0,indices.size(),3):
						var color: Color=saved.arrays[Mesh.ARRAY_COLOR][indices[j]]
						if kind=="flower" and color.r<0.4:continue # authored pale petals, not green stems
						var local: Vector3=(saved.arrays[Mesh.ARRAY_VERTEX][indices[j]]+saved.arrays[Mesh.ARRAY_VERTEX][indices[j+1]]+saved.arrays[Mesh.ARRAY_VERTEX][indices[j+2]])/3.0
						var point := origin+basis*local;var pixel := camera.unproject_position(point);var key := Vector2i(pixel*2.0)
						if pixel.x<40 or pixel.x>1880 or pixel.y<320 or pixel.y>820 or used.has(key) or not anchor_stays_visible(point):continue
						if absf(luma_at(present,pixel)-luma_at(removed,pixel))<0.02:continue
						detail_anchors[kind].append(point);used[key]=true;samples+=1
						var group := Vector2i(int(pixel.x)/320,int(pixel.y)/128);groups[group]=int(groups.get(group,0))+1
						if samples>=3 or detail_anchors[kind].size()>=48:break
					if samples:plants+=1
					if detail_anchors[kind].size()>=48:break
				if detail_anchors[kind].size()>=48:break
			if detail_anchors[kind].size()>=48:break
		check(detail_anchors[kind].size()>=12 and plants>=4,kind+" has visible far-only samples across at least four source instances")
		var best := Vector2i.ZERO
		for key: Vector2i in groups:
			if int(groups[key])>int(groups.get(best,0)):best=key
		var rectangle := Rect2i(clampi(best.x*320,0,1600),clampi(best.y*128-16,320,704),320,128)
		write_artifact(kind+"_present.png",present.get_region(rectangle).save_png_to_buffer())
		write_artifact(kind+"_removed.png",removed.get_region(rectangle).save_png_to_buffer())
		lab[kind+"_field"]={"distance_isolated":true,"distance_band_m":[60,120],"plants":plants,"rectangle":[rectangle.position.x,rectangle.position.y,320,128],"anchors":detail_anchors[kind].map(func(p:Vector3):return [p.x,p.y,p.z])}
	setup_case("fern_cluster");lab_pose("hold",0);await settle(12)

func choose_flower_view() -> void:
	# Scout actual flowers around the same source position. Geometry-based counts
	# alone can count occluded heads; score rendered far-only removal instead.
	var points: Array[Vector3]=[]
	for owner: Variant in game.ground_cover.resident:
		for species: int in [3,4,5]:
			var row: Dictionary=game.ground_cover.resident[owner][species];var t: PackedFloat32Array=row.transforms
			for i in row.ids.size():
				var origin := Vector3(t[i*12+3],t[i*12+7],t[i*12+11])
				if origin.distance_to(camera_start.origin)<60.0 or origin.distance_to(camera_start.origin)>120.0:continue
				var basis := Basis(Vector3(t[i*12],t[i*12+4],t[i*12+8]),Vector3(t[i*12+1],t[i*12+5],t[i*12+9]),Vector3(t[i*12+2],t[i*12+6],t[i*12+10]))
				for head in 2:
					var angle := head*2.399963
					points.append(origin+basis*(Vector3(cos(angle),0,sin(angle))*0.10+Vector3.UP*(0.378+head*0.07)))
	var best := -1;var chosen := camera_start;var trials := []
	for view in 12:
		camera.rotation=Vector3(deg_to_rad(-16.0),float(view)*TAU/12.0,0.0);camera_start=camera.global_transform
		setup_case("fern_cluster");lab_pose("hold",0);await settle(4);var present := root.get_texture().get_image()
		for species in [3,4,5]:source_materials[species].shader=cached_shader(Detail.control_code(authored_shader.code,"flower_removed"))
		await settle(4);var absent := root.get_texture().get_image();var score := 0
		for point in points:
			var pixel := camera.unproject_position(point)
			if camera.is_position_behind(point) or pixel.x<40 or pixel.x>1880 or pixel.y<320 or pixel.y>820:continue
			if absf(luma_at(present,pixel)-luma_at(absent,pixel))>0.02:score+=1
		trials.append(score)
		if score>best:best=score;chosen=camera_start
	camera_start=chosen;camera.global_transform=chosen
	lab["flower_view_scout"]={"candidate_heads":points.size(),"visible_counts":trials,"chosen_count":best,"camera":str(chosen),"scope":"Natural source flowers only; no new instances or density changes. Twelve yaw views scored by distance-specific removal."}

func record_path(id: String,path: String,record_pixels: bool) -> Dictionary:
	lab_pose(path,0);await settle(48)
	var row := {"case":id,"path":path,"frames":[],"hashes":[],"fern_frames":[]}
	for frame in 32:
		lab_pose(path,frame);await settle(1)
		var full := root.get_texture().get_image()
		var patch := full.get_region(tile)
		var values := PackedFloat32Array()
		for point in anchors:values.append(luma_at(full,camera.unproject_position(point)))
		# Retain raw registered samples. This is a temporal residual, not a claim
		# that all changing luminance is aliasing; hold/frozen-wind controls separate it.
		row.frames.append({"frame":frame,"samples":Array(values)})
		for kind: String in detail_anchors:
			if detail_anchors[kind].is_empty():continue
			var values_detail := []
			for point: Vector3 in detail_anchors[kind]:values_detail.append(luma_at(full,camera.unproject_position(point)))
			if not row.has(kind+"_frames"):row[kind+"_frames"]=[]
			row[kind+"_frames"].append({"frame":frame,"samples":values_detail})
		if not fern_anchors.is_empty():
			var fern_values := PackedFloat32Array()
			for point in fern_anchors:fern_values.append(luma_at(full,camera.unproject_position(point)))
			row.fern_frames.append({"frame":frame,"samples":Array(fern_values)})
		var hash := HashingContext.new();hash.start(HashingContext.HASH_SHA256)
		hash.update(patch.get_data());row.hashes.append(hash.finish().hex_encode())
		if (record_pixels and path=="strafe" or frame==0) and frame%2==0 and not budget_failed:
			patch.convert(Image.FORMAT_RGB8)
			var rgb_hash := HashingContext.new();rgb_hash.start(HashingContext.HASH_SHA256);rgb_hash.update(patch.get_data())
			var metadata := JSON.stringify({"case":id,"path":path,"frame":frame,"encoding":"lossless WebP","rgb_sha256":rgb_hash.finish().hex_encode()}).to_utf8_buffer()
			var bytes := patch.save_webp_to_buffer(false)
			if packets.get_size()+metadata.size()+bytes.size()+8>8*1024*1024:
				check(false,"lab motion packet exceeds its 8 MiB cap");budget_failed=true
			else:
				packets.put_u32(metadata.size());packets.put_data(metadata)
				packets.put_u32(bytes.size());packets.put_data(bytes);packet_count+=1
	return row

func cost_window(id: String,round_index: int) -> void:
	setup_case(id);lab_pose("strafe",0);await settle(96)
	var row := {"case":id,"round":round_index,"gpu_ms":[],"cpu_ms":[],"draws":[],"start_ticks_ms":Time.get_ticks_msec(),"start_unix_s":Time.get_unix_time_from_system()}
	# No image readbacks, encoding, analysis or archive activity during this window.
	for frame in 256:
		lab_pose("strafe",frame%64);await settle(1)
		row.gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		row.cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		row.draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	row["end_unix_s"]=Time.get_unix_time_from_system()
	lab.cost.append(row)

func idle_witness() -> Dictionary:
	var path := output.path_join("interference.live.json")
	if not FileAccess.file_exists(path):return {}
	var contents := FileAccess.get_file_as_string(path)
	if contents.is_empty():return {}
	# A missing/replaced heartbeat is an unknown environment, never permission
	# to measure. Use the error-returning parser for this external live file.
	var parser := JSON.new()
	if parser.parse(contents)!=OK:return {}
	var value: Variant=parser.data
	return value if value is Dictionary else {}

func wait_for_idle(deadline: float) -> bool:
	# Prepared lab uses no viewport GPU work while other render tests are active.
	RenderingServer.viewport_set_active(root.get_viewport_rid(),false)
	print("LAB_WAIT_IDLE")
	var next_poll := 0.0
	while Time.get_unix_time_from_system()<deadline:
		var now := Time.get_unix_time_from_system()
		if now<next_poll:await process_frame;continue
		next_poll=now+0.25
		var witness := idle_witness()
		if witness.get("monitor_ok",false) and now-witness.get("unix_s",0.0)<15.0 and witness.get("idle_since_unix_s",0.0)>0.0 and now-witness.idle_since_unix_s>=6.0:
			RenderingServer.viewport_set_active(root.get_viewport_rid(),true)
			await settle(240);return true
		await process_frame
	RenderingServer.viewport_set_active(root.get_viewport_rid(),true)
	return false

func compare(_label: String) -> void:
	for id in requested:
		var probe: String=configurations[id].get("detail_probe","none")
		detail_requested=detail_requested or probe!="none"
		for kind: String in (["stone","flower"] if probe=="combined_filtered" else [probe.get_slice("_",0)]):
			if probe!="none" and not detail_kinds.has(kind):detail_kinds.append(kind)
	if grounded_view:
		camera.global_position=base_eye
		camera.rotation.x=deg_to_rad(-12.0)
	if detail_requested:
		# Ground view hides most tiny flower heads behind grass. The user's aerial
		# report also needs a visible-source diagnostic; keep gameplay grounded.
		camera.global_position=base_eye+Vector3.UP*8.0
		camera.rotation.x=deg_to_rad(-16.0)
		lab["view"]="Source field, 8 m above normal eye, -16 degree pitch; physical gameplay remains grounded"
	camera_start=camera.global_transform
	grass=game.ground_cover.preview_meshes[2];original_grass=Filter.capture(grass)
	fern_mesh=game.ground_cover.preview_meshes[1];original_fern=FernFilter.capture(fern_mesh)
	check(preload("res://addons/world_ecosystem/filtered_fern.gd").frond_proxies(original_fern)==FernFilter.frond_proxies(original_fern),"production frond geometry equals the validated prototype")
	for owner: Variant in game.ground_cover.resident:
		var row: Dictionary=game.ground_cover.resident[owner][1]
		var transforms: PackedFloat32Array=row.transforms
		for i in row.ids.size():
			fern_roots.append(Vector3(transforms[i*12+3],transforms[i*12+7],transforms[i*12+11]))
			fern_bases.append(Basis(Vector3(transforms[i*12],transforms[i*12+4],transforms[i*12+8]),Vector3(transforms[i*12+1],transforms[i*12+5],transforms[i*12+9]),Vector3(transforms[i*12+2],transforms[i*12+6],transforms[i*12+10])))
	authored_shader=comparison_shader(AFTER)
	for mesh: Mesh in game.ground_cover.preview_meshes:
		var material: ShaderMaterial=mesh.surface_get_material(0);source_materials.append(material)
		var parameters := {}
		for parameter in ["wind_strength","grass_detail_strength","distant_self_shade","cover_clock","cover_eye","cover_projection_scale"]:
			parameters[parameter]=material.get_shader_parameter(parameter)
		original_parameters.append(parameters)
	for species: int in Detail.Species:
		detail_original[species]=Detail.capture(game.ground_cover.preview_meshes[species],species)
		var runtime: ArrayMesh=game.ground_cover.preview_meshes[species]
		var prototype := ArrayMesh.new()
		if species==0:Detail.install_stone(prototype,detail_original[species],false,true)
		else:
			Detail.install_flower(prototype,detail_original[species],true)
			check(RuntimeDetail.flower_proxies(detail_original[species])==Detail.flower_proxies(detail_original[species]),"production flower groups match measured prototype: "+str(species))
		check(runtime.get_surface_count()==2 and runtime.surface_get_arrays(1)==prototype.surface_get_arrays(1),"production detail far geometry matches measured prototype: "+str(species))
		var code: String=runtime.surface_get_material(1).shader.code.replace("\r","")
		var control: String=prototype.surface_get_material(1).shader.code.replace("\r","")
		# Deterministic lab time and explanatory comments do not change expressions.
		code=code.replace("    // Fully faded instances need no projection or silhouette-area work.\n","")
		control=control.replace("uniform float comparison_time=0.0;\n","").replace("comparison_time","TIME")
		check(code.replace(" ","").replace("\n","").replace("\r","")==control.replace(" ","").replace("\n","").replace("\r",""),"production detail shader matches measured prototype: "+str(species))
	if detail_requested:
		stone_mean=Detail.mean_color(source_materials[0])
		if "flower" in detail_kinds:await choose_flower_view()
	var original_msaa := root.msaa_3d;var original_taa := root.use_taa
	lab["source_settings"]={"msaa_enum":original_msaa,"taa":original_taa,"fov":camera.fov,"shader":FileAccess.get_sha256(AFTER)}
	if not check(source_materials.size()==9,"expected source species mapping available"):return
	if not check(original_msaa==Viewport.MSAA_2X and not original_taa,"matrix reference matches source antialiasing settings"):return
	if not check(float(original_parameters[2].grass_detail_strength)>0.0,"texture intervention has an enabled source texture to isolate"):return
	if not await establish_field():return
	var fern_trial := false
	for id in requested:fern_trial=fern_trial or configurations[id].fern_coverage
	if fern_trial:
		await establish_fern_anchors()
		if failures:return
	if detail_requested:
		await establish_detail_anchors()
		if failures:return
		var review_kind := "flower" if "flower" in detail_kinds else "stone"
		var rectangle: Array=lab[review_kind+"_field"].rectangle
		tile=Rect2i(rectangle[0],rectangle[1],rectangle[2],rectangle[3]);lab["review_field"]=review_kind
	lab.fixture_valid=true
	for item: Dictionary in plan.cases:
		var id: String=item.id
		if not requested.is_empty() and id not in requested and id!="reference":continue
		if lab_cost_only and id!="reference":continue
		setup_case(id)
		for path: String in plan.paths:
			lab.rows.append(await record_path(id,path,id in motion_cases and not lab_cost_only))
		print("LAB_CASE ",id)
		if budget_failed:break
	setup_case("reference")
	for path: String in plan.paths:
		var repeated := await record_path("reference_repeat",path,false)
		lab.rows.append(repeated)
		for row: Dictionary in lab.rows:
			if row.case=="reference" and row.path==path:check(row.hashes==repeated.hashes,"reference replay repeats exactly: "+path)
	# Independent close-view gate for the complete candidate, including lighting.
	var distant := camera_start
	camera.global_position=base_eye+Vector3(0,0,0.8);camera.look_at(base_eye-Vector3(0,1.65,0));camera_start=camera.global_transform
	setup_case("reference");lab_pose("hold",0);await settle(12)
	var nearby := root.get_texture().get_image().get_data()
	var near_cases := ["filtered_candidate","filtered_optimized"]
	for id in requested:
		if configurations[id].fern_coverage and not configurations[id].get("detail_probe","none").ends_with("fixed_low"):near_cases.append(id)
	for id in near_cases:
		setup_case(id);lab_pose("hold",0);await settle(12)
		lab.near_parity[id]=check(nearby==root.get_texture().get_image().get_data(),"full-frame nearby parity: "+id)
	camera_start=distant
	if lab_visual_only:
		lab["cost_settings"]={"skipped":true,"reason":"Explicit deterministic visual-only experiment; no timing qualification, other engine jobs may overlap."}
		setup_case("reference");camera.global_transform=distant
		root.msaa_3d=original_msaa;root.use_taa=original_taa
		return
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	var saved_fps := Engine.max_fps
	var saved_vsync := DisplayServer.window_get_vsync_mode()
	if not source_cost:Engine.max_fps=0;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	lab["cost_settings"]={"max_fps":0,"vsync":"disabled","warmup_frames":240,"case_settle_frames":96,"samples_per_round":256,"scope":"Uncapped headroom control only; normal gameplay is measured separately at source settings."}
	if source_cost:
		lab.cost_settings.max_fps=saved_fps;lab.cost_settings.vsync=saved_vsync
		lab.cost_settings.scope="Source frame cap and VSync; deterministic motion cost, physical gameplay remains a separate gate."
	setup_case("reference");lab_pose("strafe",0);await settle(240)
	# Forward/reverse ordering exposes drift; these are lab cost observations,
	# not acceptance of normal gameplay or concurrent GPU measurements.
	var ids: Array=plan.cases.map(func(c:Dictionary):return c.id)
	if not requested.is_empty():ids=Array(requested)
	if lab_interleaved_cost:
		var pair := ["filtered_candidate","filtered_optimized"]
		if lab_interleaved_cost=="fern":pair=["filtered_optimized","fern_optimized"]
		if lab_interleaved_cost=="fern_surface":pair=["fern_early","fern_optimized"]
		if lab_interleaved_cost=="fern_cluster":pair=["filtered_optimized","fern_cluster"]
		if lab_interleaved_cost in ["fern_vertex","fern_trim"]:pair=["filtered_optimized",lab_interleaved_cost]
		if lab_interleaved_cost=="complete":pair=["reference","fern_cluster"]
		if lab_interleaved_cost=="details":pair=["fern_cluster","combined_filtered"]
		if lab_interleaved_cost=="detail_clustered":pair=["fern_cluster","detail_clustered"]
		if lab_interleaved_cost=="detail_lookup":pair=["fern_cluster","detail_lookup"]
		if lab_interleaved_cost=="detail_runtime":pair=["fern_cluster","detail_runtime"]
		if lab_interleaved_cost=="detail_early":pair=["fern_cluster","detail_early"]
		if lab_interleaved_cost=="details_split":pair=["fern_cluster","stone_filtered"]
		lab.cost_settings["order"]="ABBA repeated three times; A="+pair[0]+", B="+pair[1]
		if wait_idle:
			var deadline := Time.get_unix_time_from_system()+360.0
			var accepted := 0;var repeat := 0
			var needed := 6 if lab_interleaved_cost=="details_split" else 3
			var split_counts := {"stone_filtered":0,"flower_clustered":0}
			lab.cost_settings["quiet_rounds"]=[]
			while accepted<needed and Time.get_unix_time_from_system()<deadline:
				if lab_interleaved_cost=="details_split":pair[1]="stone_filtered" if split_counts.stone_filtered<=split_counts.flower_clustered else "flower_clustered"
				if not await wait_for_idle(deadline):break
				var began := Time.get_unix_time_from_system()
				for id in [pair[0],pair[1],pair[1],pair[0]]:await cost_window(id,repeat)
				var finished := Time.get_unix_time_from_system()
				while Time.get_unix_time_from_system()<finished+6.0:await process_frame
				var witness := idle_witness();var now := Time.get_unix_time_from_system()
				if witness.get("monitor_ok",false) and now-witness.get("unix_s",0.0)<15.0 and witness.get("last_busy_unix_s",now)<began-6.0:
					lab.cost_settings.quiet_rounds.append(repeat);accepted+=1
					if lab_interleaved_cost=="details_split":split_counts[pair[1]]+=1
				print("LAB_COST_GROUP ",repeat," accepted=",accepted);repeat+=1
			check(accepted==needed,"complete paired groups without observed concurrent render jobs: "+str(needed))
			if lab_interleaved_cost=="details_split":lab.cost_settings["split_counts"]=split_counts
		else:
			for repeat in 3:
				for id in [pair[0],pair[1],pair[1],pair[0]]:await cost_window(id,repeat)
	else:
		for round_index in 2:
			if round_index==1:ids.reverse()
			for id: String in ids:await cost_window(id,round_index)
	setup_case("reference");camera.global_transform=distant
	Engine.max_fps=saved_fps;DisplayServer.window_set_vsync_mode(saved_vsync)
	root.msaa_3d=original_msaa;root.use_taa=original_taa

func run() -> void:
	var slot := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="):output=argument.trim_prefix("--check-evidence-dir=")
		if argument.begins_with("--stability-source-slot="):slot=argument.trim_prefix("--stability-source-slot=")
		if argument.begins_with("--lab-cases="):requested=argument.trim_prefix("--lab-cases=").split(",")
		if argument=="--lab-grounded-view":grounded_view=true
		if argument.begins_with("--lab-paired-cost="):lab_interleaved_cost=argument.trim_prefix("--lab-paired-cost=")
		if argument=="--lab-visual-only":lab_visual_only=true
		if argument=="--lab-source-cost":source_cost=true
		if argument=="--lab-cost-only":lab_cost_only=true
		if argument=="--lab-wait-idle":wait_idle=true
		if argument.begins_with("--lab-motion-cases="):motion_cases=argument.trim_prefix("--lab-motion-cases=").split(",")
	if output.is_empty() or slot.is_empty():push_error("Use the admitted lab runner and read-only source slot");quit(1);return
	plan=JSON.parse_string(FileAccess.get_file_as_string(PlanPath))
	lab["cost_only"]=lab_cost_only;lab["motion_cases"]=Array(motion_cases)
	lab["view"]="grounded natural grass root" if grounded_view else "saved source camera"
	for item: Dictionary in plan.cases:
		var configuration: Dictionary=plan.baseline.duplicate(true) if item.parent==null else configurations[item.parent].duplicate(true)
		configuration.merge(item.change,true);configurations[item.id]=configuration
	for id in requested:
		if not configurations.has(id):push_error("Unknown lab case: "+id);quit(1);return
	Engine.max_fps=60
	var specialized := preload("res://addons/world_ecosystem/filtered_fern.gdshader").code.replace("\r","")
	check(specialized==FernFilter.shader_code(FileAccess.get_file_as_string(AFTER),true).replace("\r",""),"production fern shader equals the validated prototype")
	var hashes := {}
	for path in [AFTER,"res://addons/world_ecosystem/filtered_grass.gd","res://addons/world_ecosystem/filtered_grass.gdshader","res://addons/world_ecosystem/filtered_fern.gd","res://addons/world_ecosystem/filtered_fern.gdshader","res://addons/world_ecosystem/filtered_detail.gd","res://addons/world_ecosystem/filtered_stone.gdshader","res://addons/world_ecosystem/woodland_mesh.gd","res://addons/world_ecosystem/ground_cover.gd"]:
		hashes[path]=FileAccess.get_sha256(path)
		write_artifact(path.get_file(),FileAccess.get_file_as_bytes(path))
	for path in ["res://tests/vegetation_lab.gd",PlanPath,"res://tests/vegetation_stability.gd","res://tests/fixtures/grass_filtered.gd","res://tests/fixtures/fern_filtered.gd","res://tests/fixtures/detail_speckles.gd","res://tests/fixtures/stone_filtered.gdshader"]:
		write_artifact(path.get_file(),FileAccess.get_file_as_bytes(path))
	for path in ["res://addons/structures/bin/structures.windows.template_debug.x86_64.dll","res://project.godot"]:hashes[path]=FileAccess.get_sha256(path)
	await actual_world(slot)
	if Detail.stone_lookup:
		lab["stone_lookup"]={"bytes":129*65*4,"max_midcell_relative_error":Detail.stone_lookup_error,"build_and_validation_us":Detail.stone_lookup_build_us,"scope":"Shared startup RF table; no mipmaps/history or per-instance CPU updates. 8192 mid-cell direction samples compared to exact projected low-mesh area."}
		check(Detail.stone_lookup_error<=0.005,"stone lookup projected area error below 0.5 percent at all validation directions")
	for path: String in hashes:check(FileAccess.get_sha256(path)==hashes[path],"production file unchanged: "+path.get_file())
	lab.merge({"checks":checks,"failures":failures,"world_input":results.get("world_input",{}),"source_sha256":hashes,"configurations":configurations,"matrix":plan,"packet_frames":packet_count,"human_approved":false,"scope":"Controlled render lab: paused world, deterministic wind/time/camera; existing source save read-only. Does not qualify physical gameplay, streaming or visual acceptance."})
	write_artifact("lab.frames",packets.data_array)
	write_artifact("lab.json",JSON.stringify(lab).to_utf8_buffer())
	var uid := "res://tests/vegetation_lab.gd.uid"
	if not FileAccess.file_exists(uid):FileAccess.open(uid,FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	var fern_uid := "res://tests/fixtures/fern_filtered.gd.uid"
	if not FileAccess.file_exists(fern_uid):FileAccess.open(fern_uid,FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	var detail_uid := "res://tests/fixtures/detail_speckles.gd.uid"
	if not FileAccess.file_exists(detail_uid):FileAccess.open(detail_uid,FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	for resource: String in ["filtered_fern.gd","filtered_fern.gdshader","filtered_detail.gd","filtered_stone.gdshader"]:
		var identity := "res://addons/world_ecosystem/"+resource+".uid"
		if not FileAccess.file_exists(identity):FileAccess.open(identity,FileAccess.WRITE).store_string(ResourceUID.id_to_text(ResourceUID.create_id())+"\n")
	print("VEGETATION_LAB failures=",failures);quit(1 if failures else 0)
