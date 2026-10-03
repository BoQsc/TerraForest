# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=60
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core: RefCounted=ClassDB.instantiate("TerrainCore")
	core.execute(Codec.command(6,[1703,2]))
	core.execute(Codec.road_bed(Vector3(400,180,400),Vector3(432,184,400),3,4))
	var epoch: int=core.execute(Codec.command(13)).decode_u32(12)
	var material=preload("res://addons/volumetric_terrain/runtime_assets.gd").make_terrain_material()
	var stage:=Node3D.new();root.add_child(stage)
	for x in [384,400,416,432]:
		for z in [384,400]:
			var decoded: Dictionary=Codec.decode_mesh(core.build_owned_region(x,z,16,1,160,192,epoch))
			if decoded.has("error"):
				push_error("Road mesh at %s,%s: %s" % [x,z,decoded]);quit(1);return
			if decoded.arrays[Mesh.ARRAY_VERTEX].is_empty(): continue
			var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,decoded.arrays)
			var instance:=MeshInstance3D.new();instance.mesh=mesh;instance.material_override=material;stage.add_child(instance)
	var sun:=DirectionalLight3D.new();stage.add_child(sun);sun.rotation_degrees=Vector3(-55,-30,0)
	var camera:=Camera3D.new();stage.add_child(camera);camera.position=Vector3(440,205,428);camera.look_at(Vector3(416,181,400));camera.current=true
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var capture:=root.get_texture().get_image()
	stage.queue_free();await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports")
	var result:=capture.save_png("res://reports/terrain_road_visual.png")
	print("PASS road shader rendered at ",capture.get_size()," save=",result)
	quit(0 if result==OK else 1)
