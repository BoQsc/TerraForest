# SPDX-License-Identifier: 0BSD
extends "res://addons/structures/packs/homestead_04/author.gd"
## Original dining props using project mesh/tube helpers and Homestead 07 cushions.

func signed_power(value: float) -> float:
	return signf(value)*pow(absf(value),0.40)

func padded(center: Vector3, size: Vector3, material: String, basis: Basis=Basis.IDENTITY) -> void:
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in 12:
		for column in 32:
			var vertices := PackedVector3Array()
			for corner: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)]:
				var u := (column+corner.x)/32.0; var v := (row+corner.y)/12.0
				var longitude := u*TAU; var latitude := (v-0.5)*PI
				var point := Vector3(signed_power(cos(latitude))*signed_power(cos(longitude)),signed_power(sin(latitude)),signed_power(cos(latitude))*signed_power(sin(longitude)))
				vertices.append(center+basis*(point*size*0.5))
			for index in [0,2,1,0,3,2]: surface.set_uv(Vector2(vertices[index].x,vertices[index].y)); surface.add_vertex(vertices[index])
	surface.generate_normals(); surface.index(); append(surface.commit(),Transform3D.IDENTITY,material)

func _init() -> void:
	super()
	for material: Material in materials.values(): material.resource_name=material.resource_name.replace("Homestead 04","Homestead 10")
	materials.wood.albedo_color=Color("795a3d"); materials.edge.albedo_color=Color("b59463"); materials.fabric.albedo_color=Color("6b8069"); materials.ceramic.albedo_color=Color("e6dec8")
	materials.ceramic.cull_mode=BaseMaterial3D.CULL_DISABLED
	materials.glass.albedo_color=Color(0.76,0.88,0.82,0.22); materials.glass.roughness=0.13
	var palette := {"cream":"e6dcc2","apple_red":"a85d49","apple_green":"88a05a","pear":"cab25f","bread":"bd904f","crust":"9c6c36"}
	for label: String in palette:
		var material := StandardMaterial3D.new(); material.resource_name="Homestead 10 / "+label; material.albedo_color=Color(palette[label]); material.roughness=0.83; material.cull_mode=BaseMaterial3D.CULL_DISABLED
		materials[label]=material
	var pixels := Image.create(128,128,false,Image.FORMAT_RGB8)
	var random := RandomNumberGenerator.new(); random.seed=170310
	for y in 128:
		for x in 128:
			var shade: float=0.83+random.randf()*0.14+0.025*sin(x*0.14+y*0.07)
			pixels.set_pixel(x,y,Color(shade,shade,shade))
	materials.bread.albedo_texture=ImageTexture.create_from_image(pixels)

func build(slug: String) -> ArrayMesh:
	surfaces.clear(); collision.clear(); wall_points.clear()
	match slug:
		"dining_table": dining_table()
		"dining_chair": dining_chair()
		"china_cabinet": china_cabinet()
		"serving_trolley": serving_trolley()
		"tea_set": tea_set()
		"serving_platter": serving_platter()
		"cutlery_tray": cutlery_tray()
		"bread_basket": bread_basket()
		"fruit_bowl": fruit_bowl()
		"table_linen": table_linen()
	var raw := ArrayMesh.new()
	for surface: SurfaceTool in surfaces.values(): surface.index(); surface.commit(raw)
	if slug in ["tea_set","serving_platter","cutlery_tray","bread_basket","fruit_bowl","table_linen"]: collision.assign([raw.get_aabb()])
	var pose := Transform3D(Basis.IDENTITY,Vector3(0,-raw.get_aabb().position.y,0))
	var mesh := ArrayMesh.new()
	for index in raw.get_surface_count():
		var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); surface.set_material(raw.surface_get_material(index)); surface.append_from(raw,index,pose); surface.commit(mesh)
	for index in collision.size(): collision[index]=pose*collision[index]
	mesh.resource_name="Homestead 10 / "+slug
	mesh.set_meta("pack_id","terraforest.homestead_10"); mesh.set_meta("collision_boxes",collision.duplicate()); mesh.set_meta("authored_size",mesh.get_aabb().size)
	return mesh

func profile_mesh(profile: Array[Vector2], material: String, pose: Transform3D=Transform3D.IDENTITY, segments: int=32) -> void:
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in segments:
		for row in profile.size()-1:
			var vertices := PackedVector3Array()
			for corner: Vector2i in [Vector2i(0,0),Vector2i(1,0),Vector2i(1,1),Vector2i(0,1)]:
				var point: Vector2=profile[row+corner.y]; var angle := (side+corner.x)*TAU/segments
				vertices.append(pose*Vector3(cos(angle)*point.x,point.y,sin(angle)*point.x))
			for index in [0,2,1,0,3,2]: surface.set_uv(Vector2(vertices[index].x,vertices[index].y)); surface.add_vertex(vertices[index])
	surface.generate_normals(); surface.index(); append(surface.commit(),Transform3D.IDENTITY,material)

func oval(center: Vector3, size: Vector3, material: String) -> void:
	var mesh := SphereMesh.new(); mesh.radius=0.5; mesh.height=1.0; mesh.radial_segments=24; mesh.rings=12
	append(mesh,Transform3D(Basis.from_scale(size),center),material)

func dining_table() -> void:
	lathe([Vector2(0,0.745),Vector2(0.57,0.745),Vector2(0.61,0.76),Vector2(0.61,0.79),Vector2(0.59,0.805),Vector2(0,0.805)],"edge",Vector3.ZERO,48)
	lathe([Vector2(0,0.10),Vector2(0.14,0.10),Vector2(0.14,0.18),Vector2(0.095,0.26),Vector2(0.075,0.45),Vector2(0.12,0.62),Vector2(0.17,0.69),Vector2(0.17,0.745),Vector2(0,0.745)],"wood")
	for index in 4:
		var direction := Vector3(cos(index*PI*0.5),0,sin(index*PI*0.5))
		strut(direction*0.06+Vector3.UP*0.19,direction*0.37+Vector3.UP*0.055,0.085,0.07,"wood")
		padded(direction*0.38+Vector3.UP*0.025,Vector3(0.14,0.05,0.12),"wood")
	collision.append(AABB(Vector3(-0.61,0.745,-0.61),Vector3(1.22,0.06,1.22)))
	collision.append(AABB(Vector3(-0.14,0.10,-0.14),Vector3(0.28,0.64,0.28)))

func dining_chair() -> void:
	for x in [-0.17,0.17]:
		for z in [-0.16,0.16]: strut(Vector3(x*1.13,0,z*1.13),Vector3(x,0.43,z),0.040,0.040,"wood")
	box(Vector3(0,0.415,0),Vector3(0.42,0.065,0.39),"wood",true)
	padded(Vector3(0,0.478,-0.01),Vector3(0.46,0.09,0.44),"fabric")
	for x in [-0.19,0.19]: strut(Vector3(x,0.40,0.15),Vector3(x,0.98,0.24),0.035,0.04,"wood")
	padded(Vector3(0,0.78,0.20),Vector3(0.39,0.36,0.085),"fabric",Basis(Vector3.RIGHT,0.15))
	box(Vector3(0,0.98,0.24),Vector3(0.42,0.035,0.04),"edge",true)
	for x in [-0.09,0.09]: sphere(Vector3(x,0.80,0.157),0.008,"teal")
	collision.append(AABB(Vector3(-0.23,0.43,-0.23),Vector3(0.46,0.10,0.44)))
	collision.append(AABB(Vector3(-0.21,0.59,0.14),Vector3(0.42,0.41,0.14)))

func pane(center: Vector3, width: float, height: float) -> void:
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [center+Vector3(-width/2,-height/2,0),center+Vector3(width/2,-height/2,0),center+Vector3(width/2,height/2,0),center+Vector3(-width/2,height/2,0)]
	for index in [0,2,1,0,3,2]: surface.set_normal(Vector3.FORWARD); surface.set_uv(Vector2(points[index].x,points[index].y)); surface.add_vertex(points[index])
	surface.index(); append(surface.commit(),Transform3D.IDENTITY,"glass")

func china_cabinet() -> void:
	for x in [-0.41,0.41]:
		for z in [-0.155,0.155]: box(Vector3(x,0.075,z),Vector3(0.075,0.15,0.075),"wood",true)
	box(Vector3(0,0.36,0),Vector3(1.0,0.46,0.42),"wood",true)
	for x in [-0.47,0.47]: box(Vector3(x,1.18,0),Vector3(0.06,1.20,0.42),"wood",true)
	box(Vector3(0,1.18,0.198),Vector3(0.94,1.2,0.025),"wood",true)
	box(Vector3(0,1.82,0),Vector3(1.07,0.085,0.47),"edge",true)
	for y in [0.615,1.01,1.405]: box(Vector3(0,y,0),Vector3(0.94,0.035,0.39),"edge",true)
	for side in 2:
		var x := -0.235+side*0.47
		box(Vector3(x,0.355,-0.222),Vector3(0.43,0.35,0.025),"edge")
		box(Vector3(x,0.355,-0.238),Vector3(0.37,0.29,0.006),"wood")
		for offset in [-0.219,0.219]: box(Vector3(x+offset,1.19,-0.226),Vector3(0.025,1.18,0.035),"wood",true)
		for y in [0.61,1.77]: box(Vector3(x,y,-0.226),Vector3(0.45,0.032,0.035),"wood",true)
		pane(Vector3(x,1.19,-0.230),0.41,1.13)
		collision.append(AABB(Vector3(x-0.205,0.625,-0.232),Vector3(0.41,1.13,0.008)))
		var handle_x: float=x+0.17 if side==0 else x-0.17
		rod(Vector3(handle_x,1.05,-0.255),Vector3(handle_x,1.16,-0.255),0.006,"brass")
		cylinder(Vector3(handle_x,0.355,-0.251),0.012,0.009,"brass",Vector3.FORWARD)
	for shelf in 3:
		var y := 0.635+shelf*0.395
		for side in 2:
			var x := -0.235+side*0.47
			if shelf==1:
				var pose := Transform3D(Basis(Vector3.RIGHT,PI*0.5),Vector3(x,y+0.13,0.06))
				profile_mesh([Vector2(0,0),Vector2(0.09,0),Vector2(0.14,0.018),Vector2(0.14,0.027),Vector2(0.09,0.012),Vector2(0,0.012)],"ceramic",pose)
			else:
				for plate in 3: profile_mesh([Vector2(0,0),Vector2(0.08,0),Vector2(0.12,0.01),Vector2(0.12,0.02),Vector2(0.08,0.01),Vector2(0,0.01)],"ceramic",Transform3D(Basis.IDENTITY,Vector3(x,y+plate*0.025,0)))

func serving_trolley() -> void:
	for x in [-0.30,0.30]:
		for z in [-0.16,0.16]:
			rod(Vector3(x,0.075,z),Vector3(x,0.72,z),0.014,"brass")
			cylinder(Vector3(x,0.055,z),0.055,0.035,"rubber",Vector3.RIGHT)
			cylinder(Vector3(x+0.019,0.055,z),0.018,0.003,"brass",Vector3.RIGHT)
			collision.append(AABB(Vector3(x-0.027,0,z-0.055),Vector3(0.054,0.72,0.11)))
	for y in [0.20,0.66]:
		box(Vector3(0,y,0),Vector3(0.69,0.035,0.43),"edge",true)
		for z in [-0.205,0.205]: box(Vector3(0,y+0.035,z),Vector3(0.69,0.04,0.017),"wood",true)
		for x in [-0.336,0.336]: box(Vector3(x,y+0.035,0),Vector3(0.017,0.04,0.40),"wood",true)
	tube(PackedVector3Array([Vector3(0.30,0.67,-0.16),Vector3(0.40,0.83,-0.16),Vector3(0.40,0.83,0.16),Vector3(0.30,0.67,0.16)]),0.014,"brass")
	collision.append(AABB(Vector3(0.30,0.70,-0.175),Vector3(0.115,0.145,0.35)))

func spout(points: PackedVector3Array, radii: PackedFloat32Array) -> void:
	var outer: Array[PackedVector3Array]=[]; var inner: Array[PackedVector3Array]=[]
	for index in points.size():
		var tangent := (points[mini(index+1,points.size()-1)]-points[maxi(index-1,0)]).normalized()
		var basis := Basis(Quaternion(Vector3.UP,tangent))
		var a := PackedVector3Array(); var b := PackedVector3Array()
		for side in 16:
			var direction := basis*Vector3(cos(side*TAU/16),0,sin(side*TAU/16))
			a.append(points[index]+direction*radii[index]); b.append(points[index]+direction*(radii[index]-0.004))
		outer.append(a); inner.append(b)
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for shell in 2:
		var rings: Array[PackedVector3Array]=outer if shell==0 else inner
		for row in rings.size()-1:
			for side in 16:
				var next := (side+1)%16
				var vertices := [rings[row][side],rings[row+1][side],rings[row+1][next],rings[row][next]]
				for corner in [0,1,2,0,2,3] if shell==0 else [0,2,1,0,3,2]: surface.set_uv(Vector2(vertices[corner].x,vertices[corner].y)); surface.add_vertex(vertices[corner])
	for row in [0,points.size()-1]:
		for side in 16:
			var next := (side+1)%16
			var vertices := [outer[row][side],outer[row][next],inner[row][next],inner[row][side]]
			for corner in [0,1,2,0,2,3]: surface.set_uv(Vector2(vertices[corner].x,vertices[corner].y)); surface.add_vertex(vertices[corner])
	surface.generate_normals(); surface.index(); append(surface.commit(),Transform3D.IDENTITY,"ceramic")

func tea_set() -> void:
	box(Vector3(0,0.012,0),Vector3(0.57,0.024,0.42),"edge")
	var origin := Vector3(-0.12,0.026,0)
	lathe([Vector2(0,0.005),Vector2(0.065,0.005),Vector2(0.10,0.045),Vector2(0.108,0.11),Vector2(0.082,0.175),Vector2(0.055,0.19),Vector2(0.047,0.19),Vector2(0.074,0.165),Vector2(0.096,0.11),Vector2(0.087,0.05),Vector2(0.055,0.018),Vector2(0,0.018)],"ceramic",origin)
	lathe([Vector2(0,0.195),Vector2(0.060,0.195),Vector2(0.060,0.205),Vector2(0.035,0.22),Vector2(0,0.225)],"ceramic",origin)
	sphere(origin+Vector3(0,0.235,0),0.012,"brass")
	spout(PackedVector3Array([origin+Vector3(0.075,0.08,0),origin+Vector3(0.15,0.11,0),origin+Vector3(0.19,0.18,0),origin+Vector3(0.235,0.21,0)]),PackedFloat32Array([0.028,0.025,0.019,0.016]))
	tube(PackedVector3Array([origin+Vector3(-0.075,0.16,0),origin+Vector3(-0.15,0.18,0),origin+Vector3(-0.17,0.10,0),origin+Vector3(-0.14,0.04,0),origin+Vector3(-0.08,0.04,0)]),0.011,"ceramic")
	for z in [-0.115,0.115]:
		var center := Vector3(0.15,0.026,z)
		lathe([Vector2(0,0),Vector2(0.05,0),Vector2(0.085,0.008),Vector2(0.085,0.015),Vector2(0.05,0.01),Vector2(0,0.01)],"ceramic",center)
		lathe([Vector2(0,0.012),Vector2(0.036,0.012),Vector2(0.06,0.080),Vector2(0.061,0.090),Vector2(0.054,0.09),Vector2(0.029,0.022),Vector2(0,0.022)],"ceramic",center)
		hoop(center+Vector3(0,0.09,0),0.055,0.061,"teal")
		hoop(center+Vector3(0.064,0.057,0),0.021,0.028,"ceramic",Basis(Vector3.RIGHT,PI*0.5))

func serving_platter() -> void:
	profile_mesh([Vector2(0,0.004),Vector2(0.11,0.004),Vector2(0.15,0.025),Vector2(0.16,0.031),Vector2(0.16,0.038),Vector2(0.147,0.038),Vector2(0.106,0.014),Vector2(0,0.014)],"ceramic",Transform3D(Basis.from_scale(Vector3(1.45,1,1)),Vector3.ZERO),48)
	var ring := TorusMesh.new(); ring.inner_radius=0.149; ring.outer_radius=0.156; ring.rings=48; ring.ring_segments=8
	append(ring,Transform3D(Basis.from_scale(Vector3(1.45,1,1)),Vector3(0,0.038,0)),"teal")

func cutlery_tray() -> void:
	box(Vector3(0,0.008,0),Vector3(0.31,0.016,0.245),"wood")
	for x in [-0.147,0.147,-0.05,0.05]: box(Vector3(x,0.025,0),Vector3(0.012,0.034,0.245),"edge")
	for z in [-0.116,0.116]: box(Vector3(0,0.025,z),Vector3(0.30,0.034,0.012),"edge")
	for x in [-0.10,0,0.10]:
		padded(Vector3(x,0.024,0.05),Vector3(0.014,0.009,0.095),"steel")
		rod(Vector3(x,0.027,0.01),Vector3(x,0.027,-0.04),0.003,"steel")
	profile_mesh([Vector2(0,0),Vector2(0.015,0),Vector2(0.023,0.009),Vector2(0.021,0.012),Vector2(0.012,0.004),Vector2(0,0.004)],"steel",Transform3D(Basis.from_scale(Vector3(0.8,1,1.3)),Vector3(-0.10,0.027,-0.062)),24)
	box(Vector3(0,0.028,-0.045),Vector3(0.022,0.006,0.018),"steel")
	for index in 4: box(Vector3(-0.009+index*0.006,0.028,-0.073),Vector3(0.003,0.005,0.045),"steel")
	polygon(PackedVector3Array([Vector3(0.096,0.03,0.012),Vector3(0.119,0.03,-0.02),Vector3(0.118,0.03,-0.092),Vector3(0.096,0.03,-0.102)]),"steel")

func bread_basket() -> void:
	profile_mesh([Vector2(0,0.005),Vector2(0.11,0.005),Vector2(0.11,0.018),Vector2(0,0.018)],"wood",Transform3D(Basis.from_scale(Vector3(1.4,1,0.85)),Vector3.ZERO))
	for row in 8:
		var y := 0.02+row*0.012; var radius := 0.113+row*0.005
		var mesh := TorusMesh.new(); mesh.inner_radius=radius-0.003; mesh.outer_radius=radius+0.003; mesh.rings=40; mesh.ring_segments=6
		append(mesh,Transform3D(Basis.from_scale(Vector3(1.4,1,0.85)),Vector3(0,y,0)),"rope")
	for index in 32:
		var angle := index*TAU/32
		rod(Vector3(cos(angle)*0.113*1.4,0.018,sin(angle)*0.113*0.85),Vector3(cos(angle)*0.15*1.4,0.11,sin(angle)*0.15*0.85),0.003,"rope")
	padded(Vector3(-0.065,0.075,0),Vector3(0.21,0.115,0.16),"bread")
	for z in [-0.058,0.058]: oval(Vector3(0.095,0.063,z),Vector3(0.12,0.09,0.10),"bread")
	for index in 3: rod(Vector3(-0.12+index*0.05,0.133,-0.035),Vector3(-0.10+index*0.05,0.133,0.035),0.003,"cream")

func fruit_bowl() -> void:
	lathe([Vector2(0,0.005),Vector2(0.065,0.005),Vector2(0.135,0.06),Vector2(0.16,0.10),Vector2(0.151,0.108),Vector2(0.125,0.07),Vector2(0.056,0.018),Vector2(0,0.018)],"ceramic")
	hoop(Vector3(0,0.103,0),0.151,0.16,"teal")
	for index in 4:
		var angle := index*TAU/4
		var center := Vector3(cos(angle)*0.068,0.10,sin(angle)*0.068)
		oval(center,Vector3(0.105,0.10,0.10),"apple_red" if index%2==0 else "apple_green")
		rod(center+Vector3.UP*0.042,center+Vector3(0.005,0.067,0),0.003,"wood")
	oval(Vector3(0,0.14,0),Vector3(0.095,0.11,0.09),"pear")
	oval(Vector3(0.01,0.20,0),Vector3(0.05,0.075,0.05),"pear")
	rod(Vector3(0.01,0.231,0),Vector3(0.015,0.255,0.005),0.003,"wood")
	polygon(PackedVector3Array([Vector3(0.012,0.236,0),Vector3(0.045,0.248,-0.012),Vector3(0.072,0.245,0),Vector3(0.042,0.238,0.012)]),"teal")

func table_linen() -> void:
	for layer in 2:
		var y := 0.024+layer*0.040
		padded(Vector3(0,y,0),Vector3(0.52,0.045,0.35),"linen")
		for x in [-0.20,0.20]: box(Vector3(x,y+0.023,0),Vector3(0.015,0.001,0.29),"teal")
	for index in 3:
		var x := -0.16+index*0.16
		padded(Vector3(x,0.105,-0.02),Vector3(0.13,0.03,0.20),"fabric",Basis(Vector3.UP,-0.10+index*0.10))
		rod(Vector3(x-0.05,0.121,-0.08),Vector3(x+0.05,0.121,-0.08),0.0016,"linen")
