# SPDX-License-Identifier: 0BSD
# Offline authoring. Shared opaque mesh and one runtime collision proxy.
extends SceneTree
func _initialize() -> void:
	var wood:=SurfaceTool.new();wood.begin(Mesh.PRIMITIVE_TRIANGLES)
	var iron:=SurfaceTool.new();iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count:=0
	# Horizontal boards with recessed seams, closed bottom and inset lid boards.
	for row in 4:
		for z in [-0.32,0.32]:
			box(wood,Vector3(0,0.105+row*0.14,z),Vector3(1.2,0.135,0.06));count+=1
		for x in [-0.57,0.57]:
			box(wood,Vector3(x,0.105+row*0.14,0),Vector3(0.06,0.135,0.58));count+=1
	box(wood,Vector3(0,0.035,0),Vector3(1.2,0.07,0.7));count+=1
	for plank in 5:
		box(wood,Vector3(-0.488+plank*0.244,0.66,0),Vector3(0.239,0.12,0.74));count+=1
	# Raised end battens join the lid and sides, reinforcing the chest silhouette.
	for x in [-0.48,0.48]:
		box(wood,Vector3(x,0.735,0),Vector3(0.085,0.03,0.74));count+=1
		for z in [-0.357,0.357]:
			box(wood,Vector3(x,0.3,z),Vector3(0.085,0.58,0.025));count+=1
	# Small dark latch and hinges, kept in one shared second surface.
	box(iron,Vector3(0,0.57,0.383),Vector3(0.10,0.20,0.025));count+=1
	box(iron,Vector3(0,0.53,0.405),Vector3(0.035,0.035,0.025));count+=1
	for x in [-0.4,0.4]:
		box(iron,Vector3(x,0.59,-0.38),Vector3(0.09,0.16,0.02));count+=1
	var timber:=StandardMaterial3D.new();timber.albedo_color=Color("b49b79");timber.roughness=0.9
	timber.albedo_texture=load("res://addons/structures/textures/terraforest/wood_albedo.png")
	timber.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	wood.set_material(timber)
	var metal:=StandardMaterial3D.new();metal.albedo_color=Color("393d3b");metal.metallic=0.65;metal.roughness=0.7;iron.set_material(metal)
	var mesh:=wood.commit();iron.commit(mesh);mesh.resource_name="Wooden storage chest"
	var result:=ResourceSaver.save(mesh,"res://addons/structures/prefabs/storage_chest_model.tres")
	print("BAKED storage chest triangles=",count*12," result=",result)
	quit(0 if result==OK else 1)
func box(surface: SurfaceTool,center: Vector3,size: Vector3) -> void:
	var mesh:=BoxMesh.new();mesh.size=size
	surface.append_from(mesh,0,Transform3D(Basis.IDENTITY,center))
