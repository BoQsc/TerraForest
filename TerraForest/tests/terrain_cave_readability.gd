extends SceneTree

var failures:=0
var viewport:=SubViewport.new()
var material:=ShaderMaterial.new()
var surface:=MeshInstance3D.new()

func check(passed:bool,label:String)->void:
	print("PASS " if passed else "FAIL ",label)
	if not passed:failures+=1

func _initialize()->void:
	_run.call_deferred()

func sample(sky:float,minimum:Variant)->Color:
	var quad:=QuadMesh.new()
	quad.size=Vector2(2,2)
	var arrays:=quad.get_mesh_arrays()
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var visibility:=PackedVector2Array()
	var identities:=PackedVector2Array()
	var colors:=PackedColorArray()
	for index in vertices.size():
		visibility.append(Vector2(sky,0))
		identities.append(Vector2(5,1))
		colors.append(Color(0,0,0,1))
	arrays[Mesh.ARRAY_TEX_UV]=visibility
	arrays[Mesh.ARRAY_TEX_UV2]=identities
	arrays[Mesh.ARRAY_COLOR]=colors
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	surface.mesh=mesh
	material.set_shader_parameter("minimum_cave_fill",minimum)
	for frame in 8:await process_frame
	await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image()
	return image.get_pixel(64,64)

func brightness(color:Color)->float:
	return maxf(color.r,maxf(color.g,color.b))

func _run()->void:
	viewport.size=Vector2i(128,128)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var camera:=Camera3D.new()
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=2.5
	camera.position=Vector3(0,0,3)
	viewport.add_child(camera)
	material.shader=load("res://addons/volumetric_terrain/terrain.gdshader")
	var image:=Image.create(4,4,false,Image.FORMAT_RGBA8)
	image.fill(Color(.5,.5,.5,1))
	var texture:=ImageTexture.create_from_image(image)
	for parameter in ["grass","gravel","sand","snow"]:material.set_shader_parameter(parameter,texture)
	surface.material_override=material
	viewport.add_child(surface)
	var strict:=await sample(0.0,0.0)
	var faint:=await sample(0.0,null)
	var exterior:=await sample(1.0,null)
	var exterior_strict:=await sample(1.0,0.0)
	var shaded:=await sample(.25,null)
	var shaded_strict:=await sample(.25,0.0)
	check(brightness(strict)<=.004,"zero-fill control stays black without lights")
	check(brightness(faint)>.01&&brightness(faint)<brightness(exterior)*.6,"default makes zero-sky terrain faintly visible rather than fullbright")
	check(exterior.is_equal_approx(exterior_strict),"open-sky terrain brightness is unchanged")
	check(shaded.is_equal_approx(shaded_strict),"ordinary nonzero sky shading is unchanged")
	print("CAVE_READABILITY_COLORS strict=",strict," faint=",faint," exterior=",exterior," shaded=",shaded)
	viewport.free()
	await process_frame
	print("TERRAIN_CAVE_READABILITY failures=",failures)
	quit(1 if failures else 0)
