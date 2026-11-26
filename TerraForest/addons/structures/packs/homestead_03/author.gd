# SPDX-License-Identifier: 0BSD
extends "res://addons/structures/packs/homestead_02/author.gd"
## Original washroom geometry. Reuses the project's 0BSD offline mesh helpers.

func _init() -> void:
	super()
	for material: Material in materials.values(): material.resource_name=material.resource_name.replace("Homestead 02","Homestead 03")
	materials.ceramic.albedo_color=Color("e3ddc7")
	materials.teal.cull_mode=BaseMaterial3D.CULL_DISABLED
	var zinc := StandardMaterial3D.new(); zinc.resource_name="Homestead 03 / galvanized zinc"; zinc.albedo_color=Color("9da8a6"); zinc.metallic=0.72; zinc.roughness=0.47; materials.zinc=zinc
	var silver := StandardMaterial3D.new(); silver.resource_name="Homestead 03 / inexpensive mirror finish"; silver.albedo_color=Color("9dbbc0"); silver.metallic=0.58; silver.roughness=0.18; materials.silver=silver
	var glint := StandardMaterial3D.new(); glint.resource_name="Homestead 03 / glass highlight"; glint.albedo_color=Color(0.85,0.94,0.94,0.25); glint.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; glint.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; materials.glint=glint
	var soap := StandardMaterial3D.new(); soap.resource_name="Homestead 03 / pale soap"; soap.albedo_color=Color("d6c89e"); soap.roughness=0.68; materials.soap=soap
	var straw := StandardMaterial3D.new(); straw.resource_name="Homestead 03 / broom fibre"; straw.albedo_color=Color("bd9a60"); straw.roughness=0.94; materials.straw=straw

func shaped_lathe(profile: Array[Vector2], material: String, pose: Transform3D) -> void:
	var previous := surfaces
	surfaces={}; lathe(profile,material)
	var surface: SurfaceTool=surfaces[material]
	var mesh := surface.commit()
	surfaces=previous; append(mesh,pose,material)

func build(slug: String) -> ArrayMesh:
	surfaces.clear(); collision.clear(); wall_points.clear()
	match slug:
		"bathtub": bathtub()
		"toilet": toilet()
		"mirror": mirror()
		"towel_rail": towel_rail()
		"towels": towels()
		"soap_dish": soap_dish()
		"paper_holder": paper_holder()
		"laundry_tub": laundry_tub()
		"washboard": washboard()
		"broom_set": broom_set()
	var raw := ArrayMesh.new()
	for surface: SurfaceTool in surfaces.values(): surface.index(); surface.commit(raw)
	var pose := Transform3D(Basis(Vector3.RIGHT,deg_to_rad(12)) if slug=="washboard" else Basis.IDENTITY,Vector3.ZERO)
	pose.origin.y=-(pose*raw.get_aabb()).position.y
	var mesh := ArrayMesh.new()
	for index in raw.get_surface_count():
		var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); surface.set_material(raw.surface_get_material(index)); surface.append_from(raw,index,pose); surface.commit(mesh)
	for index in collision.size(): collision[index]=pose*collision[index]
	for index in wall_points.size(): wall_points[index]=pose*wall_points[index]
	mesh.resource_name="Homestead 03 / "+slug
	mesh.set_meta("pack_id","terraforest.homestead_03"); mesh.set_meta("collision_boxes",collision.duplicate()); mesh.set_meta("authored_size",mesh.get_aabb().size)
	if not wall_points.is_empty(): mesh.set_meta("wall_support_points",wall_points)
	return mesh

func bathtub() -> void:
	shaped_lathe([Vector2(0,0.16),Vector2(0.33,0.16),Vector2(0.43,0.23),Vector2(0.51,0.57),Vector2(0.52,0.62),Vector2(0.49,0.65),Vector2(0.46,0.62),Vector2(0.45,0.56),Vector2(0.37,0.28),Vector2(0.28,0.23),Vector2(0,0.23)],"ceramic",Transform3D(Basis.from_scale(Vector3(1.8,1,0.85)),Vector3.ZERO))
	var rim := TorusMesh.new(); rim.inner_radius=0.47; rim.outer_radius=0.52; rim.rings=48; rim.ring_segments=8
	append(rim,Transform3D(Basis.from_scale(Vector3(1.8,0.6,0.85)),Vector3(0,0.625,0)),"ceramic")
	for x in [-0.57,0.57]:
		for z in [-0.24,0.24]:
			rod(Vector3(x,0.04,z),Vector3(x*0.85,0.21,z*0.85),0.035,"iron"); sphere(Vector3(x,0.045,z),0.045,"iron")
	rod(Vector3(0.69,0.30,0.11),Vector3(0.69,0.85,0.11),0.023,"brass")
	rod(Vector3(0.69,0.85,0.11),Vector3(0.69,0.85,-0.04),0.023,"brass")
	rod(Vector3(0.69,0.85,-0.04),Vector3(0.69,0.79,-0.04),0.025,"brass")
	for x in [0.58,0.80]: cylinder(Vector3(x,0.69,0.09),0.035,0.025,"brass")
	cylinder(Vector3(0.49,0.25,0),0.035,0.012,"zinc")
	collision.append(AABB(Vector3(-0.68,0.03,-0.30),Vector3(1.36,0.21,0.60)))
	for z in [-0.36,0.36]: collision.append(AABB(Vector3(-0.82,0.24,z-0.07),Vector3(1.64,0.40,0.14)))
	for x in [-0.79,0.79]: collision.append(AABB(Vector3(x-0.14,0.24,-0.35),Vector3(0.28,0.40,0.70)))

func toilet() -> void:
	lathe([Vector2(0,0.005),Vector2(0.15,0.005),Vector2(0.16,0.05),Vector2(0.10,0.20),Vector2(0.13,0.28),Vector2(0,0.28)],"ceramic",Vector3(0,0,0.03))
	shaped_lathe([Vector2(0,0.24),Vector2(0.10,0.24),Vector2(0.20,0.33),Vector2(0.26,0.47),Vector2(0.26,0.51),Vector2(0.23,0.52),Vector2(0.21,0.47),Vector2(0.14,0.34),Vector2(0.07,0.31),Vector2(0,0.31)],"ceramic",Transform3D(Basis.from_scale(Vector3(0.92,1,1.18)),Vector3(0,0,-0.10)))
	var seat := TorusMesh.new(); seat.inner_radius=0.205; seat.outer_radius=0.265; seat.rings=40; seat.ring_segments=10
	append(seat,Transform3D(Basis.from_scale(Vector3(0.94,0.52,1.19)),Vector3(0,0.54,-0.10)),"wood")
	box(Vector3(0,0.77,0.235),Vector3(0.43,0.48,0.19),"ceramic",true)
	box(Vector3(0,1.025,0.235),Vector3(0.47,0.05,0.23),"ceramic")
	cylinder(Vector3(-0.15,0.88,0.125),0.022,0.035,"brass",Vector3.FORWARD)
	box(Vector3(-0.12,0.88,0.103),Vector3(0.09,0.018,0.025),"brass")
	rod(Vector3(0,0.23,0.22),Vector3(0,0.56,0.22),0.04,"zinc")
	collision.append(AABB(Vector3(-0.16,0,-0.14),Vector3(0.32,0.32,0.34)))
	for x in [-0.20,0.20]: collision.append(AABB(Vector3(x-0.04,0.31,-0.40),Vector3(0.08,0.25,0.58)))
	for z in [-0.35,0.15]: collision.append(AABB(Vector3(-0.20,0.31,z-0.04),Vector3(0.40,0.25,0.08)))

func mirror() -> void:
	var oval := CylinderMesh.new(); oval.top_radius=0.30; oval.bottom_radius=0.30; oval.height=0.02; oval.radial_segments=48; oval.rings=1
	var flat := Basis.from_scale(Vector3(0.86,1.22,1))*Basis(Vector3.RIGHT,PI*0.5)
	append(oval,Transform3D(flat,Vector3(0,0.40,-0.01)),"silver")
	var frame := TorusMesh.new(); frame.inner_radius=0.30; frame.outer_radius=0.335; frame.rings=48; frame.ring_segments=8
	append(frame,Transform3D(flat,Vector3(0,0.40,-0.01)),"edge")
	box(Vector3(-0.07,0.46,-0.023),Vector3(0.012,0.40,0.002),"glint",false,Basis(Vector3.FORWARD,-0.42))
	box(Vector3(-0.035,0.46,-0.024),Vector3(0.006,0.36,0.002),"glint",false,Basis(Vector3.FORWARD,-0.42))
	collision.append(AABB(Vector3(-0.29,0,-0.045),Vector3(0.58,0.81,0.075)))
	wall_points=PackedVector3Array([Vector3(0,0.66,0.025),Vector3(-0.16,0.20,0.025),Vector3(0.16,0.20,0.025)])

func towel_rail() -> void:
	for x in [-0.35,0.35]:
		box(Vector3(x,0.43,0.02),Vector3(0.055,0.075,0.18),"zinc",true)
		wall_points.append(Vector3(x,0.43,0.11))
	cylinder(Vector3(0,0.43,-0.09),0.018,0.76,"zinc",Vector3.RIGHT)
	for strip in 18:
		var x0 := -0.24+strip*0.0267; var x1 := x0+0.0267
		var z0 := -0.125-0.012*cos(strip*TAU/6); var z1 := -0.125-0.012*cos((strip+1)*TAU/6)
		polygon(PackedVector3Array([Vector3(x0,0.035,z0),Vector3(x1,0.035,z1),Vector3(x1,0.44,z1),Vector3(x0,0.44,z0)]),"fabric")
		rod(Vector3(x0,0.075,z0-0.001),Vector3(x1,0.075,z1-0.001),0.007,"linen")
		polygon(PackedVector3Array([Vector3(x0,0.25,-0.07),Vector3(x1,0.25,-0.07),Vector3(x1,0.44,z1),Vector3(x0,0.44,z0)]),"fabric")
	collision.append(AABB(Vector3(-0.25,0.025,-0.15),Vector3(0.50,0.43,0.10)))

func towels() -> void:
	for layer in 3:
		var y := 0.035+layer*0.065
		var color := "linen" if layer==1 else "fabric"
		box(Vector3(0,y,0.025),Vector3(0.40,0.06,0.25),color)
		cylinder(Vector3(0,y,-0.10),0.030,0.40,color,Vector3.RIGHT)
		box(Vector3(0,y-0.002,-0.13),Vector3(0.37,0.003,0.003),"teal")
		for x in [-0.155,0.155]: box(Vector3(x,y+0.032,0.02),Vector3(0.014,0.003,0.24),"linen" if layer!=1 else "teal")
	collision.append(AABB(Vector3(-0.20,0,-0.13),Vector3(0.40,0.20,0.28)))

func soap_dish() -> void:
	shaped_lathe([Vector2(0,0.005),Vector2(0.07,0.005),Vector2(0.09,0.015),Vector2(0.10,0.035),Vector2(0.092,0.042),Vector2(0.080,0.023),Vector2(0,0.018)],"ceramic",Transform3D(Basis.from_scale(Vector3(1.45,1,0.95)),Vector3.ZERO))
	var bar := SphereMesh.new(); bar.radius=0.5; bar.height=1; bar.radial_segments=24; bar.rings=12
	append(bar,Transform3D(Basis.from_scale(Vector3(0.18,0.060,0.105)),Vector3(0,0.049,0)),"soap")
	for x in [-0.027,0,0.027]: box(Vector3(x,0.078,0),Vector3(0.015,0.001,0.005),"linen")
	collision.append(AABB(Vector3(-0.145,0,-0.095),Vector3(0.29,0.08,0.19)))

func paper_holder() -> void:
	for x in [-0.14,0.14]:
		box(Vector3(x,0.17,-0.035),Vector3(0.025,0.055,0.15),"zinc",true)
		wall_points.append(Vector3(x,0.17,0.04))
	cylinder(Vector3(0,0.17,-0.105),0.012,0.30,"iron",Vector3.RIGHT)
	shaped_lathe([Vector2(0.025,-0.105),Vector2(0.067,-0.105),Vector2(0.067,0.105),Vector2(0.025,0.105),Vector2(0.025,-0.105)],"linen",Transform3D(Basis(Vector3.FORWARD,PI*0.5),Vector3(0,0.17,-0.105)))
	cylinder(Vector3(-0.109,0.17,-0.105),0.024,0.005,"wood",Vector3.RIGHT)
	box(Vector3(0,0.076,-0.170),Vector3(0.21,0.13,0.003),"linen")
	collision.append(AABB(Vector3(-0.11,0.005,-0.175),Vector3(0.22,0.235,0.145)))

func laundry_tub() -> void:
	lathe([Vector2(0,0.008),Vector2(0.25,0.008),Vector2(0.27,0.035),Vector2(0.34,0.34),Vector2(0.33,0.36),Vector2(0.32,0.34),Vector2(0.25,0.045),Vector2(0,0.03)],"zinc")
	hoop(Vector3(0,0.35,0),0.32,0.35,"zinc")
	for index in 16:
		var angle := index*TAU/16.0
		rod(Vector3(cos(angle)*0.266,0.05,sin(angle)*0.266),Vector3(cos(angle)*0.335,0.33,sin(angle)*0.335),0.0035,"zinc")
	for x in [-0.345,0.345]: hoop(Vector3(x,0.32,0),0.067,0.078,"iron",Basis(Vector3.FORWARD,PI*0.5))
	collision.append(AABB(Vector3(-0.27,0,-0.27),Vector3(0.54,0.05,0.54)))
	for z in [-0.30,0.30]: collision.append(AABB(Vector3(-0.28,0.04,z-0.04),Vector3(0.56,0.32,0.08)))
	for x in [-0.30,0.30]: collision.append(AABB(Vector3(x-0.04,0.04,-0.28),Vector3(0.08,0.32,0.56)))

func washboard() -> void:
	for x in [-0.205,0.205]: box(Vector3(x,0.37,0),Vector3(0.055,0.74,0.065),"wood",true)
	for y in [0.04,0.57,0.72]: box(Vector3(0,y,0),Vector3(0.44,0.05,0.065),"edge",true)
	box(Vector3(0,0.31,0.006),Vector3(0.35,0.49,0.018),"zinc",true)
	for index in 23: cylinder(Vector3(0,0.08+index*0.021,-0.012),0.009,0.35,"zinc",Vector3.RIGHT)
	box(Vector3(0,0.575,-0.01),Vector3(0.35,0.028,0.085),"edge")

func broom_set() -> void:
	rod(Vector3(-0.15,0.20,0),Vector3(-0.035,1.32,0.08),0.017,"wood")
	sphere(Vector3(-0.035,1.32,0.08),0.022,"edge")
	box(Vector3(-0.15,0.20,0),Vector3(0.28,0.065,0.10),"wood",true)
	for column in 19:
		for depth in [-0.035,0,0.035]:
			var x := -0.27+column*0.0133
			rod(Vector3(x,0.18,depth),Vector3(-0.15+(x+0.15)*1.18,0.015,depth*1.2),0.0055,"straw")
	polygon(PackedVector3Array([Vector3(0.12,0.008,-0.14),Vector3(0.39,0.008,-0.14),Vector3(0.37,0.045,0.12),Vector3(0.14,0.045,0.12)]),"teal")
	box(Vector3(0.255,0.06,0.12),Vector3(0.24,0.06,0.018),"teal",true)
	for x in [0.13,0.38]: box(Vector3(x,0.032,-0.005),Vector3(0.015,0.035,0.26),"teal")
	rod(Vector3(0.255,0.06,0.13),Vector3(0.255,0.13,0.35),0.014,"iron")
	hoop(Vector3(0.255,0.14,0.39),0.028,0.040,"iron")
	collision.append(AABB(Vector3(-0.33,0,-0.055),Vector3(0.36,0.22,0.11)))
	collision.append(AABB(Vector3(-0.17,0.20,-0.02),Vector3(0.17,1.15,0.13)))
	collision.append(AABB(Vector3(0.11,0,-0.15),Vector3(0.30,0.08,0.31)))
