# SPDX-License-Identifier: 0BSD
extends SceneTree
## Offline conversion only. Runtime still loads shared meshes into native batches.
const SOURCE := "res://authoring/bg5/"
const RECIPE := SOURCE + "runtime_recipe.json"
const TEXTURES := "res://addons/structures/textures/bg5/"
const OUTPUT := "res://mods/bg5_runtime/"
const PREFABS := "res://addons/structures/prefabs/"
const STAGED := "res://reports/bg5_runtime/staged/"
var texture_records: Dictionary = {}
var sources: Dictionary = {}
var transforms: Dictionary = {}
var receipt: Dictionary = {}
var failed := false

func _initialize() -> void: run.call_deferred()
func fail(message: String) -> void:
	failed = true
	push_error("BG5 bake: " + message)
func vec(values: Array) -> Vector3: return Vector3(values[0],values[1],values[2])
func numbers(value: Vector3) -> Array: return [value.x,value.y,value.z]
func bounds_of(parts: Array, transform: Transform3D = Transform3D.IDENTITY, prefix: String = "") -> AABB:
	var bounds := AABB()
	var first := true
	for part: MeshInstance3D in parts:
		if not String(part.name).begins_with(prefix): continue
		var box: AABB = transform * part.global_transform * part.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	return bounds

func material_texture(texture: Texture2D, normal: bool, edge: int, extracting: bool, mirror: bool) -> Texture2D:
	var pixels := texture.get_image()
	if pixels.is_compressed(): pixels.decompress()
	pixels.clear_mipmaps()
	pixels.convert(Image.FORMAT_RGBA8)
	var ratio := minf(1.0,float(edge/(2 if mirror else 1))/maxi(pixels.get_width(),pixels.get_height()))
	if ratio < 1: pixels.resize(maxi(1,roundi(pixels.get_width()*ratio)),maxi(1,roundi(pixels.get_height()*ratio)),Image.INTERPOLATE_LANCZOS)
	if mirror:
		# StandardMaterial3D cannot express glTF MIRRORED_REPEAT. Bake one
		# two-by-two mirrored period and halve UV scale, preserving wrap semantics.
		var size := pixels.get_size()
		var tiled := Image.create(size.x*2,size.y*2,false,Image.FORMAT_RGBA8)
		tiled.blit_rect(pixels,Rect2i(Vector2i.ZERO,size),Vector2i.ZERO)
		pixels.flip_x();tiled.blit_rect(pixels,Rect2i(Vector2i.ZERO,size),Vector2i(size.x,0))
		pixels.flip_y();tiled.blit_rect(pixels,Rect2i(Vector2i.ZERO,size),size)
		pixels.flip_x();tiled.blit_rect(pixels,Rect2i(Vector2i.ZERO,size),Vector2i(0,size.y))
		pixels = tiled
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256);digest.update(pixels.get_data())
	var key := digest.finish().hex_encode().left(24) + ("_normal" if normal else "")
	var path := TEXTURES + key + ".png"
	texture_records[path] = {"width":pixels.get_width(),"height":pixels.get_height(),"normal":normal}
	if extracting:
		if pixels.save_png(path) != OK: fail("Could not write texture " + path)
		return texture
	var result: Texture2D = load(path)
	if result == null: fail("Import textures before mesh bake: " + path)
	return result

func materials(parts: Array, edge: int, extracting: bool, mirror: bool) -> void:
	var replacements := {}
	for part: MeshInstance3D in parts:
		for surface in part.mesh.get_surface_count():
			var original: StandardMaterial3D = part.mesh.surface_get_material(surface)
			if original == null: fail("Missing standard PBR material");return
			var identity := original.get_instance_id()
			if not replacements.has(identity):
				var material: StandardMaterial3D = original.duplicate()
				for property: String in ["albedo_texture","normal_texture","roughness_texture","metallic_texture","ao_texture","orm_texture","emission_texture"]:
					var texture: Texture2D = material.get(property)
					if texture != null: material.set(property,material_texture(texture,property=="normal_texture",edge,extracting,mirror))
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				if mirror:
					material.texture_repeat = true
					material.uv1_scale *= Vector3(0.5,0.5,1)
				replacements[identity] = material
			part.mesh.surface_set_material(surface,replacements[identity])

func load_master(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path,state) != OK: fail("Could not read " + path);return null
	var scene: Node3D = doc.generate_scene(state)
	root.add_child(scene)
	for player: AnimationPlayer in scene.find_children("*","AnimationPlayer",true,false):
		player.stop();player.active = false
	return scene

func bake(entry: Dictionary, recipe: Dictionary, extracting: bool) -> void:
	var path: String = SOURCE + entry.source
	sources[path] = FileAccess.get_sha256(path)
	var scene := load_master(path)
	if scene == null: return
	var group: Node3D = scene if not entry.has("group") else scene.find_child(entry.group,true,false)
	if group == null: fail("Missing source group " + str(entry));scene.free();return
	var parts: Array = group.find_children("*","MeshInstance3D",true,false)
	if parts.is_empty(): fail("No mesh parts " + entry.name);scene.free();return
	materials(parts,int(recipe.texture_long_edge),extracting,bool(entry.get("mirror_repeat",false)))
	if extracting or failed: scene.free();return
	var transform := Transform3D.IDENTITY
	if entry.has("transform_from"):
		transform = transforms[entry.transform_from]
	else:
		# Exact 180-degree turn keeps canonical axes and shared closed poses stable.
		var rotation := Basis.from_scale(Vector3(-1,1,-1)) if entry.rotation_y == 180 else Basis.IDENTITY
		var target := AABB(vec(entry.target_position),vec(entry.target_size))
		var rotated := Transform3D(rotation,Vector3.ZERO)
		if entry.fit == "hinge":
			# Align the source's actual hinge axis with legacy X=Z=0. Fit the
			# timber leaf to one metre by 2.2 m; hardware may extend at the hinge.
			rotated.origin = -(rotation * group.global_position)
			var wood := bounds_of(parts,rotated,"leaf")
			var all_parts := bounds_of(parts,rotated)
			var scale := Vector3(target.size.x/wood.end.x,target.size.y/wood.size.y,0.11/maxf(absf(all_parts.position.z),absf(all_parts.end.z)))
			transform = Transform3D(Basis.from_scale(scale),Vector3(0,-wood.position.y*scale.y,0)) * rotated
		else:
			var bounds := bounds_of(parts,rotated)
			var scale := target.size / bounds.size
			transform = Transform3D(Basis.from_scale(scale),target.position-bounds.position*scale) * rotated
	transforms[entry.name] = transform
	# SurfaceTool canonicalizes vertex formats before joining by material.
	# ImporterMesh.merge alone retains several tiny recess surfaces with
	# different compressed source formats even when their material is shared.
	var builders: Dictionary = {}
	for part: MeshInstance3D in parts:
		for surface in part.mesh.get_surface_count():
			var material := part.mesh.surface_get_material(surface)
			if not builders.has(material):
				var builder := SurfaceTool.new()
				builder.begin(Mesh.PRIMITIVE_TRIANGLES);builder.set_material(material)
				builders[material] = builder
			builders[material].append_from(part.mesh,surface,transform*part.global_transform)
	var combined := ArrayMesh.new()
	for builder: SurfaceTool in builders.values():
		builder.index();builder.optimize_indices_for_cache();builder.commit(combined)
	var merged := ImporterMesh.from_mesh(combined)
	merged.generate_lods(60.0,60.0,[])
	var mesh := merged.get_mesh()
	mesh.resource_name = "BG5 " + String(entry.name).capitalize()
	var vertices := 0
	var triangles := 0
	var lods := 0
	for surface in merged.get_surface_count():
		var arrays := merged.get_surface_arrays(surface)
		vertices += arrays[Mesh.ARRAY_VERTEX].size()
		triangles += arrays[Mesh.ARRAY_INDEX].size()/3
		lods += merged.get_surface_lod_count(surface)
	if mesh.get_surface_count()>8 or vertices>32768:
		fail("Runtime geometry budget exceeded: " + entry.name);scene.free();return
	if entry.has("prefab"):
		var destination: String = PREFABS + entry.prefab
		# Preserve existing native collision authoring exactly, independent of art.
		if entry.has("collision_boxes"):
			var boxes: Array[AABB] = []
			for values: Array in entry.collision_boxes: boxes.append(AABB(vec(values.slice(0,3)),vec(values.slice(3,6))))
			mesh.set_meta("collision_boxes",boxes)
		# Publish from Python after this engine exits, avoiding Windows resource
		# readers holding the destination during a bake/import session.
		if ResourceSaver.save(mesh,STAGED+entry.prefab) != OK:
			fail("Could not stage " + destination);scene.free();return
	var instance := MeshInstance3D.new()
	instance.name = entry.name
	instance.mesh = mesh
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_scene(instance,state) != OK: fail("GLB export failed " + entry.name)
	var output: String = OUTPUT + entry.name + ".glb"
	var staged_glb: String = STAGED + entry.name + ".glb"
	var file := FileAccess.open(staged_glb,FileAccess.WRITE)
	var buffer := document.generate_buffer(state)
	file.store_buffer(buffer);file.close()
	var box := mesh.get_aabb()
	var record := {"source":path,"source_parts":parts.size(),"surfaces":mesh.get_surface_count(),"vertices":vertices,"triangles":triangles,"lod_levels":lods,"position":numbers(box.position),"size":numbers(box.size),"glb":output,"glb_sha256":FileAccess.get_sha256(staged_glb),"glb_bytes":buffer.size(),"transform":{"x":numbers(transform.basis.x),"y":numbers(transform.basis.y),"z":numbers(transform.basis.z),"origin":numbers(transform.origin)}}
	if entry.has("prefab"):
		record.prefab = PREFABS + entry.prefab
		record.prefab_sha256 = FileAccess.get_sha256(STAGED+entry.prefab)
	receipt[entry.name] = record
	instance.free();scene.free()
	print("BG5_RUNTIME ",entry.name," parts=",parts.size()," surfaces=",mesh.get_surface_count()," triangles=",triangles," lods=",lods)

func run() -> void:
	var recipe: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECIPE))
	var extracting := "--textures" in OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(TEXTURES);DirAccess.make_dir_recursive_absolute(OUTPUT);DirAccess.make_dir_recursive_absolute(STAGED)
	for entry: Dictionary in recipe.assets:
		bake(entry,recipe,extracting)
		if failed: quit(1);return
	var result := {"schema":1,"license":"CC0-1.0","engine":Engine.get_version_info().string,"sources":sources,"recipe_sha256":FileAccess.get_sha256(RECIPE),"tool_sha256":FileAccess.get_sha256("res://tools/bake_bg5_runtime.gd"),"textures":texture_records,"assets":receipt}
	FileAccess.open(TEXTURES+"textures.json" if extracting else STAGED+"bake.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  ")+"\n")
	quit()
