# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func query(core: RefCounted,p: Vector3) -> PackedByteArray:
	var packet:=Codec.point_command(p);packet.encode_u32(0,26);return core.execute(packet)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core: RefCounted=ClassDB.instantiate("TerrainCore")
	core.execute(Codec.command(6,[2468,3]))
	var found: Dictionary={}
	for x in range(320,448,4):
		for z in range(320,448,4):
			for y in range(8,56,4):
				var p:=Vector3(x,y,z);var result:=query(core,p)
				var id:=result.decode_u32(12)
				if id in [8,9] and result.decode_float(16)<0 and absf(result.decode_float(20))>0.9: found[id]=p
				if found.size()==2: break
			if found.size()==2: break
		if found.size()==2: break
	check(found.size()==2,"seeded solid terrain contains iron and copper")
	if found.size()!=2: quit(1);return
	var p: Vector3=found[8]
	var before:=query(core,p)
	check(before==query(core,p),"material identity and continuous weight are deterministic")
	check(Codec.reply_ok(core.execute(Codec.brush(p,p,0.75,0,false,1))),"mining intersects ore-bearing terrain")
	var mined:=query(core,p)
	check(mined.decode_u32(12)==8 and mined.decode_float(16)>0,"excavation changes density while retaining geological identity")
	var saved: PackedByteArray=core.execute(Codec.command(4)).slice(12)
	core.execute(Codec.command(6,[999,1]))
	var packet:=Codec.command(5);packet.append_array(saved)
	check(Codec.reply_ok(core.execute(packet)) and query(core,p)==mined,"mined vein survives save reload exactly")
	var epoch: int=core.execute(Codec.command(13)).decode_u32(12)
	var mesh: Dictionary=Codec.decode_mesh(core.build_owned_region(int(p.x)/16*16,int(p.z)/16*16,16,1,int(p.y)/32*32,int(p.y)/32*32+32,epoch))
	var visible:=false
	if not mesh.has("error"):
		for uv: Vector2 in mesh.arrays[Mesh.ARRAY_TEX_UV2]:
			if uv.x>0.01 and uv.x<=1.0: visible=true
	check(visible,"excavated surface carries continuous iron weight to renderer")
	if DisplayServer.get_name()!="headless":
		preload("res://addons/presentation/fullscreen_policy.gd").apply(root)
		Engine.max_fps=60
		var center:=p+Vector3(0,2.5,0)
		core.execute(Codec.brush(center,center,3.5,0,false,1))
		var scene:=Node3D.new();root.add_child(scene)
		var material:=preload("res://addons/volumetric_terrain/runtime_assets.gd").make_terrain_material()
		for x in range(floori((center.x-5)/16)*16,floori((center.x+5)/16)*16+1,16):
			for z in range(floori((center.z-5)/16)*16,floori((center.z+5)/16)*16+1,16):
				mesh=Codec.decode_mesh(core.build_owned_region(x,z,16,1,floori(center.y/32)*32,floori(center.y/32)*32+32,epoch))
				if mesh.has("error") or mesh.arrays[Mesh.ARRAY_VERTEX].is_empty(): continue
				var surface:=MeshInstance3D.new();var resource:=ArrayMesh.new();resource.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,mesh.arrays)
				surface.mesh=resource;surface.material_override=material;scene.add_child(surface)
		var camera:=Camera3D.new();scene.add_child(camera);camera.position=center;camera.near=0.02;camera.look_at(p+Vector3(0.5,0,0.5));camera.make_current()
		check(scene.get_child_count()>1,"visual fixture contains real terrain geometry")
		var lamp:=OmniLight3D.new();lamp.position=center;lamp.omni_range=12;lamp.light_energy=2;scene.add_child(lamp)
		for i in range(8): await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://reports/iron_vein.png")==OK,"real excavated ore mesh rendered with terrain shader")
		scene.free()
	core.execute(Codec.command(6,[2468,2]))
	check(query(core,p).decode_u32(12)==0 and query(core,p).decode_float(20)==0,"previous generator retains its original material field")
	quit(1 if failures else 0)
