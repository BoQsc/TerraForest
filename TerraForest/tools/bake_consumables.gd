# SPDX-License-Identifier: 0BSD
extends SceneTree
var surfaces:Dictionary={}

func add_mesh(mesh:Mesh,transform:Transform3D,color:Color,metal:bool=false)->void:
	if not surfaces.has(metal):
		var builder:=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES);surfaces[metal]=builder
	var arrays:=mesh.surface_get_arrays(0)
	var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		for index in vertices.size():indices.append(index)
	var builder:SurfaceTool=surfaces[metal]
	for index in indices:
		builder.set_color(color);builder.set_normal((transform.basis.inverse().transposed()*normals[index]).normalized());builder.add_vertex(transform*vertices[index])

func box(size:Vector3,position:Vector3,color:Color)->void:
	var mesh:=BoxMesh.new();mesh.size=size;add_mesh(mesh,Transform3D(Basis.IDENTITY,position),color)

func sphere(size:Vector3,position:Vector3,color:Color,segments:int=16)->void:
	var mesh:=SphereMesh.new();mesh.radius=.5;mesh.height=1;mesh.radial_segments=segments;mesh.rings=6
	add_mesh(mesh,Transform3D(Basis.IDENTITY.scaled(size),position),color)

func cylinder(radius:float,height:float,position:Vector3,color:Color,metal:bool=false)->void:
	var mesh:=CylinderMesh.new();mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.height=height;mesh.radial_segments=24;mesh.rings=1
	add_mesh(mesh,Transform3D(Basis.IDENTITY,position),color,metal)

func book(journal:bool)->void:
	var cover:=Color("654938") if journal else Color("344c42")
	box(Vector3(.18,.008,.25),Vector3(0,-.024,0),cover);box(Vector3(.18,.008,.25),Vector3(0,.024,0),cover)
	box(Vector3(.166,.04,.236),Vector3(.003,0,0),Color("b7b19a"));box(Vector3(.012,.052,.25),Vector3(-.087,0,0),cover.darkened(.22))
	for index in 9:
		box(Vector3(.166,.0006,.001),Vector3(.003,-.016+index*.004,.1184),Color("777563"))
	box(Vector3(.115,.0006,.041),Vector3(0,.0284,-.025),Color("a49772"))
	for index in 3:box(Vector3(.07-index*.012,.0007,.003),Vector3(0,.029,-.035+index*.01),cover)
	if journal:box(Vector3(.013,.001,.251),Vector3(.06,.029,0),Color("272626"))
	else:box(Vector3(.012,.002,.055),Vector3(.03,-.018,.13),Color("8c4b42"))

func letter()->void:
	box(Vector3(.2,.004,.13),Vector3.ZERO,Color("c3b79b"))
	box(Vector3(.19,.0008,.057),Vector3(0,.0026,-.032),Color("dbd0b8"))
	box(Vector3(.18,.0005,.0012),Vector3(0,.0032,-.003),Color("8d816b"))
	cylinder(.014,.003,Vector3(.014,.004,.001),Color("6e3b31"))
	box(Vector3(.032,.0006,.02),Vector3(.065,.003,.035),Color("8a8b76"))

func beans()->void:
	cylinder(.065,.15,Vector3.ZERO,Color("7b8587"),true)
	cylinder(.0655,.096,Vector3(0,-.003,0),Color("b8b18c"))
	for height in [-.071,.071]:cylinder(.068,.006,Vector3(0,height,0),Color("9ba3a1"),true)
	for height in [-.057,.051]:cylinder(.0658,.006,Vector3(0,height,0),Color("40574b"))
	box(Vector3(.025,.004,.014),Vector3(0,.078,.012),Color("536264"))
	for index in 3:sphere(Vector3(.02,.012,.006),Vector3(-.022+index*.022,-.008,.0658),Color("6f563c"),12)

func bread()->void:
	sphere(Vector3(.29,.105,.17),Vector3.ZERO,Color("956937"),24)
	sphere(Vector3(.26,.087,.145),Vector3(0,.014,0),Color("b38a50"),24)
	for index in 4:
		var mesh:=BoxMesh.new();mesh.size=Vector3(.008,.002,.07)
		add_mesh(mesh,Transform3D(Basis(Vector3.UP,-.4),Vector3(-.085+index*.055,.057,0)),Color("70502f"))
	for index in 16:
		var angle:float=index*2.39996;var radius:float=.02+float(index%4)*.015
		sphere(Vector3(.004,.002,.008),Vector3(cos(angle)*radius,.058,sin(angle)*radius*.6),Color("c9b27b"),8)

func berries()->void:
	box(Vector3(.115,.006,.105),Vector3(0,-.016,0),Color("ac9272"))
	for side in [-1,1]:
		var mesh:=BoxMesh.new();mesh.size=Vector3(.025,.003,.105)
		add_mesh(mesh,Transform3D(Basis(Vector3.BACK,side*.55),Vector3(side*.052,-.006,0)),Color("b5a087"))
	for index in 12:
		var angle:float=index*2.39996;var radius:float=.012+float(index%3)*.012
		sphere(Vector3(.022,.017,.025),Vector3(cos(angle)*radius,.004+float(index%2)*.009,sin(angle)*radius),Color("583839") if index%2 else Color("493742"),12)

func _initialize()->void:
	DirAccess.make_dir_recursive_absolute("res://addons/player_runtime/art/consumables")
	for identity in range(214,220):
		surfaces={}
		match identity:
			214:book(false)
			215:letter()
			216:book(true)
			217:beans()
			218:bread()
			219:berries()
		var mesh:=ArrayMesh.new()
		for metal:bool in surfaces:
			var material:=StandardMaterial3D.new();material.vertex_color_use_as_albedo=true;material.roughness=.44 if metal else .86;material.metallic=.65 if metal else 0.0
			var builder:SurfaceTool=surfaces[metal];builder.set_material(material);builder.index();builder.commit(mesh)
		if ResourceSaver.save(mesh,"res://addons/player_runtime/art/consumables/%d.res"%identity,ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
		var drop:=ArrayMesh.new();var bounds:=mesh.get_aabb();var scale_factor:=.35/maxf(bounds.size.x,maxf(bounds.size.y,bounds.size.z))
		for surface in mesh.get_surface_count():
			var builder:=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES);builder.append_from(mesh,surface,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*scale_factor),-bounds.get_center()*scale_factor));builder.set_material(mesh.surface_get_material(surface));builder.commit(drop)
		if ResourceSaver.save(drop,"res://addons/player_runtime/art/drops/%d.res"%identity,ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
		print("CONSUMABLE_MESH ",identity," vertices=",mesh.surface_get_array_len(0)," bounds=",bounds)
	print("CONSUMABLE_BAKE complete");quit()
