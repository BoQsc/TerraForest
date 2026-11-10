# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var output:=""
func find_mesh(node:Node)->MeshInstance3D:
	if node is MeshInstance3D:return node
	for child:Node in node.get_children():
		var found:=find_mesh(child)
		if found!=null:return found
	return null
func _initialize()->void:run.call_deferred()
func rendered()->Image:
	for frame in 3:await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--roof-output="):output=arg.get_slice("=",1)
	root.size=Vector2i(512,320)
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld");root.add_child(blocks)
	blocks.set_cells(PackedInt32Array([0,0,0,blocks.encode_block(1,0,3,5)]));blocks.flush_bakes()
	var source:ShaderMaterial=find_mesh(blocks).mesh.surface_get_material(0)
	blocks.visible=false
	var reference:ShaderMaterial=source.duplicate()
	var shader:=Shader.new()
	shader.code=source.shader.code.replace("float layer =", "float layer = 9.0; //")
	reference.shader=shader
	var quad:=QuadMesh.new();quad.size=Vector2(7,4)
	var arrays:Array=quad.get_mesh_arrays();var codes:=PackedVector2Array()
	# Stress categorical IDs with roundoff-sized error; interpolation must never
	# turn a zinc face into non-metal shading. The reference fixes the layer to 9.
	for index in arrays[Mesh.ARRAY_VERTEX].size():codes.append(Vector2(9.0+(.000002 if index%2 else -.000002),0))
	arrays[Mesh.ARRAY_TEX_UV2]=codes
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var view:=MeshInstance3D.new();view.mesh=mesh;view.material_override=source;root.add_child(view)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color(.2,.3,.4)
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.4;root.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-20,-30,0);light.light_energy=2;root.add_child(light)
	var camera:=Camera3D.new();root.add_child(camera)
	var differences:Array=[]
	for step in 8:
		camera.position=Vector3(-1.1+step*.31,.13+step*.07,5.5);camera.look_at(Vector3.ZERO)
		view.material_override=source;var actual:Image=await rendered()
		view.material_override=reference;var expected:Image=await rendered()
		# Use the actual viewport dimensions: project window policy may override
		# the requested size. Reject blank/background-only comparisons.
		if expected.get_pixel(expected.get_width()/2,expected.get_height()/2).is_equal_approx(expected.get_pixel(0,0)):
			failures+=1
		var different:=0
		for y in range(actual.get_height()/3,actual.get_height()*2/3):
			for x in range(actual.get_width()/3,actual.get_width()*2/3):
				var a:=actual.get_pixel(x,y);var b:=expected.get_pixel(x,y)
				if maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))>2.0/255:different+=1
		differences.append(different)
		if different>0:failures+=1
		if step==0 and not output.is_empty():actual.save_png(output.path_join("roof_actual.png"));expected.save_png(output.path_join("roof_reference.png"))
	print("ROOF_MATERIAL_STABILITY differing_pixels=",differences," failures=",failures)
	blocks.free();view.free();camera.free();light.free();environment.free();await process_frame
	quit(1 if failures else 0)
