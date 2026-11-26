# SPDX-License-Identifier: 0BSD
extends "res://addons/structures/packs/homestead_04/author.gd"
## Original entryway/porch geometry; inherited offline mesh/tube helpers are 0BSD.

func _init() -> void:
	super()
	for material: Material in materials.values(): material.resource_name=material.resource_name.replace("Homestead 04","Homestead 08")
	materials.wood.albedo_color=Color("71614b"); materials.edge.albedo_color=Color("aa9069"); materials.teal.albedo_color=Color("647c67")
	var palette := {"terra":"b97751","soil":"443b2d","leaf":"557352","leaf_light":"7c9460","leaf_dark":"355c45","mud":"89704b","boot":"48564a","leather":"805e43","ochre":"b59a5f"}
	for label: String in palette:
		var material := StandardMaterial3D.new(); material.resource_name="Homestead 08 / "+label; material.albedo_color=Color(palette[label]); material.roughness=0.90; material.cull_mode=BaseMaterial3D.CULL_DISABLED
		if label in ["terra","soil","mud"]: material.albedo_texture=texture(false)
		materials[label]=material
	var weave := Image.create(128,64,false,Image.FORMAT_RGB8)
	var random := RandomNumberGenerator.new(); random.seed=170308
	for y in 64:
		for x in 128:
			var shade: float=0.69+random.randf()*0.16+0.12*float(x%3==0)+0.04*float(y%4==0)
			weave.set_pixel(x,y,Color(shade,shade,shade))
	var coir := StandardMaterial3D.new(); coir.resource_name="Homestead 08 / original coir weave"; coir.albedo_color=Color("a98b56"); coir.albedo_texture=ImageTexture.create_from_image(weave); coir.roughness=1.0; materials.coir=coir

func build(slug: String) -> ArrayMesh:
	surfaces.clear(); collision.clear(); wall_points.clear()
	match slug:
		"hall_console": hall_console()
		"entry_bench": entry_bench()
		"shoe_rack": shoe_rack()
		"umbrella_stand": umbrella_stand()
		"doormat": doormat()
		"key_rack": key_rack()
		"mailbox": mailbox()
		"muddy_boots": muddy_boots()
		"planter": planter()
		"watering_can": watering_can()
	var raw := ArrayMesh.new()
	for surface: SurfaceTool in surfaces.values(): surface.index(); surface.commit(raw)
	if slug in ["muddy_boots","watering_can"]: collision.assign([raw.get_aabb()])
	var pose := Transform3D(Basis.IDENTITY,Vector3(0,-raw.get_aabb().position.y,0))
	var mesh := ArrayMesh.new()
	for index in raw.get_surface_count():
		var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); surface.set_material(raw.surface_get_material(index)); surface.append_from(raw,index,pose); surface.commit(mesh)
	for index in collision.size(): collision[index]=pose*collision[index]
	for index in wall_points.size(): wall_points[index]=pose*wall_points[index]
	mesh.resource_name="Homestead 08 / "+slug
	mesh.set_meta("pack_id","terraforest.homestead_08"); mesh.set_meta("collision_boxes",collision.duplicate()); mesh.set_meta("authored_size",mesh.get_aabb().size)
	if not wall_points.is_empty(): mesh.set_meta("wall_support_points",wall_points)
	return mesh

func oval(center: Vector3, size: Vector3, material: String, basis: Basis=Basis.IDENTITY) -> void:
	var mesh := SphereMesh.new(); mesh.radius=0.5; mesh.height=1.0; mesh.radial_segments=24; mesh.rings=12
	append(mesh,Transform3D(basis*Basis.from_scale(size),center),material)

func hall_console() -> void:
	box(Vector3(0,0.805,0),Vector3(1.10,0.055,0.29),"edge",true)
	box(Vector3(0,0.715,0.005),Vector3(1.00,0.13,0.24),"wood",true)
	for x in [-0.47,0.47]:
		for z in [-0.09,0.09]: box(Vector3(x,0.34,z),Vector3(0.045,0.68,0.045),"wood",true)
	for x in [-0.247,0.247]:
		box(Vector3(x,0.72,-0.122),Vector3(0.475,0.105,0.022),"wood")
		rod(Vector3(x-0.035,0.72,-0.143),Vector3(x+0.035,0.72,-0.143),0.006,"brass")
	for index in 5: box(Vector3(0,0.15,-0.085+index*0.043),Vector3(0.98,0.025,0.032),"wood",true)
	for x in [-0.47,0.47]: box(Vector3(x,0.13,0),Vector3(0.045,0.025,0.23),"wood",true)

func entry_bench() -> void:
	for x in [-0.49,0.49]:
		tube(PackedVector3Array([Vector3(x,0.015,-0.20),Vector3(x,0.37,-0.17),Vector3(x,0.42,0.17),Vector3(x,0.015,0.20)]),0.022,"teal")
		rod(Vector3(x,0.38,0.16),Vector3(x,0.82,0.22),0.018,"teal")
		collision.append(AABB(Vector3(x-0.025,0,-0.225),Vector3(0.05,0.43,0.45)))
	for index in 5: box(Vector3(0,0.435,-0.165+index*0.081),Vector3(1.13,0.045,0.065),"edge",true)
	for y in [0.62,0.77]: box(Vector3(0,y,0.20+(y-0.62)*0.15),Vector3(1.10,0.10,0.04),"wood",true,Basis(Vector3.RIGHT,0.13))
	for x in [-0.49,0.49]:
		for z in [-0.15,0.15]: cylinder(Vector3(x,0.46,z),0.008,0.003,"steel")

func shoe_rack() -> void:
	for x in [-0.36,0.36]:
		for z in [-0.13,0.13]: box(Vector3(x,0.275,z),Vector3(0.025,0.55,0.025),"teal",true)
	for y in [0.055,0.28,0.505]:
		for index in 5: box(Vector3(0,y,-0.12+index*0.06),Vector3(0.76,0.022,0.035),"edge",true)
	for shelf in 2:
		for pair in 2:
			for side in 2: shoe(Vector3(-0.25+pair*0.34+side*0.12,0.067+shelf*0.225,0),"leather" if shelf==0 else "teal")

func shoe(origin: Vector3, material: String) -> void:
	oval(origin+Vector3(0,0.013,-0.025),Vector3(0.095,0.026,0.23),"rubber")
	oval(origin+Vector3(0,0.045,-0.045),Vector3(0.090,0.068,0.19),material)
	oval(origin+Vector3(0,0.075,0.045),Vector3(0.083,0.075,0.09),material)
	oval(origin+Vector3(0,0.108,0.044),Vector3(0.057,0.007,0.052),"iron")
	for index in 3: rod(origin+Vector3(-0.023,0.082,-0.040+index*0.017),origin+Vector3(0.023,0.082,-0.029+index*0.017),0.0017,"linen")

func umbrella_stand() -> void:
	lathe([Vector2(0,0.006),Vector2(0.12,0.006),Vector2(0.12,0.43),Vector2(0.108,0.43),Vector2(0.108,0.025),Vector2(0,0.025)],"teal")
	for y in [0.04,0.40]: hoop(Vector3(0,y,0),0.118,0.126,"steel")
	for index in 16:
		var angle := index*TAU/16
		rod(Vector3(cos(angle)*0.120,0.06,sin(angle)*0.120),Vector3(cos(angle)*0.120,0.38,sin(angle)*0.120),0.002,"teal")
	folded_umbrella(Vector3(-0.035,0,0),Vector3(-0.09,0,-0.015),"ochre")
	folded_umbrella(Vector3(0.04,0.035,0.025),Vector3(0.07,0,0.02),"fabric")
	collision.append(AABB(Vector3(-0.126,0,-0.126),Vector3(0.252,0.43,0.252)))
	collision.append(AABB(Vector3(-0.18,0.43,-0.085),Vector3(0.40,0.73,0.18)))

func folded_umbrella(origin: Vector3, lean: Vector3, material: String) -> void:
	rod(origin+lean*0.05+Vector3.UP*0.04,origin+lean*1.01+Vector3.UP*1.01,0.005,"steel")
	var profile := [Vector2(0.008,0.20),Vector2(0.025,0.36),Vector2(0.058,0.71),Vector2(0.064,0.80),Vector2(0.045,0.85),Vector2(0.006,0.86)]
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in profile.size()-1:
		for side in 16:
			var vertices := PackedVector3Array()
			for corner: Vector2i in [Vector2i(0,0),Vector2i(0,1),Vector2i(1,1),Vector2i(1,0)]:
				var point: Vector2=profile[index+corner.x]; var angle := (side+corner.y)*TAU/16
				var radius: float=point.x*(0.83 if (side+corner.y)%2 else 1.0)
				vertices.append(origin+lean*point.y+Vector3(cos(angle)*radius,point.y,sin(angle)*radius))
			for corner in [0,2,1,0,3,2]: surface.set_uv(Vector2(vertices[corner].x,vertices[corner].y)); surface.add_vertex(vertices[corner])
	surface.generate_normals(); surface.index(); append(surface.commit(),Transform3D.IDENTITY,material)
	var handle := PackedVector3Array()
	for index in 17:
		var angle := PI-index*PI/16
		handle.append(origin+lean*1.01+Vector3(0.05+cos(angle)*0.05,1.01+sin(angle)*0.05,0))
	handle.append(origin+lean*1.01+Vector3(0.10,0.98,0)); tube(handle,0.011,"wood")
	box(origin+lean*0.69+Vector3(0,0.69,-0.05),Vector3(0.09,0.018,0.012),"wood")

func doormat() -> void:
	box(Vector3(0,0.004,0),Vector3(0.76,0.008,0.44),"rubber",true)
	box(Vector3(0,0.012,0),Vector3(0.735,0.012,0.415),"coir",true)
	for z in [-0.19,0.19]: box(Vector3(0,0.019,z),Vector3(0.70,0.003,0.014),"wood")
	for x in [-0.34,0.34]: box(Vector3(x,0.019,0),Vector3(0.014,0.003,0.38),"wood")
	for index in 30: rod(Vector3(-0.32+index*0.022,0.020,-0.17),Vector3(-0.32+index*0.022,0.020,0.17),0.0013,"rope")

func key_rack() -> void:
	box(Vector3(0,0.18,0),Vector3(0.40,0.15,0.03),"wood",true)
	for x in [-0.17,0.17]: cylinder(Vector3(x,0.21,-0.018),0.007,0.004,"steel",Vector3.FORWARD)
	for index in 5:
		var x := -0.14+index*0.07
		tube(PackedVector3Array([Vector3(x,0.17,-0.015),Vector3(x,0.15,-0.045),Vector3(x,0.16,-0.065)]),0.004,"brass")
		if index%2==0:
			hoop(Vector3(x,0.13,-0.060),0.015,0.018,"steel",Basis(Vector3.RIGHT,PI*0.5))
			rod(Vector3(x,0.112,-0.062),Vector3(x,0.055,-0.062),0.004,"brass")
			for tooth in 2: box(Vector3(x+0.006,0.06+tooth*0.009,-0.062),Vector3(0.015,0.005,0.008),"brass")
	wall_points=PackedVector3Array([Vector3(-0.17,0.21,0.015),Vector3(0.17,0.21,0.015)])

func mailbox() -> void:
	box(Vector3(0,0.21,0),Vector3(0.32,0.39,0.125),"teal",true)
	box(Vector3(0,0.195,-0.067),Vector3(0.285,0.29,0.009),"teal")
	for x in [-0.139,0.139]: box(Vector3(x,0.195,-0.074),Vector3(0.006,0.29,0.004),"iron")
	box(Vector3(0,0.345,-0.067),Vector3(0.235,0.019,0.008),"iron")
	box(Vector3(0,0.375,-0.015),Vector3(0.35,0.018,0.17),"teal",false,Basis(Vector3.RIGHT,-0.13))
	box(Vector3(0,0.255,-0.078),Vector3(0.115,0.035,0.006),"brass")
	box(Vector3(0,0.255,-0.083),Vector3(0.092,0.021,0.002),"linen")
	cylinder(Vector3(0.095,0.14,-0.08),0.010,0.007,"brass",Vector3.FORWARD)
	box(Vector3(0.095,0.14,-0.085),Vector3(0.002,0.010,0.002),"iron")
	wall_points=PackedVector3Array([Vector3(-0.11,0.35,0.0625),Vector3(0.11,0.35,0.0625)])

func muddy_boots() -> void:
	for side in 2:
		var origin := Vector3(-0.09+side*0.18,0,0.025 if side==0 else -0.025)
		oval(origin+Vector3(0,0.018,-0.04),Vector3(0.145,0.036,0.31),"rubber")
		oval(origin+Vector3(0,0.069,-0.06),Vector3(0.14,0.12,0.27),"boot")
		lathe([Vector2(0.063,0.07),Vector2(0.057,0.16),Vector2(0.073,0.33),Vector2(0.079,0.35),Vector2(0.067,0.35),Vector2(0.061,0.325),Vector2(0.047,0.15),Vector2(0.052,0.10)],"boot",origin+Vector3(0,0,0.035))
		hoop(origin+Vector3(0,0.35,0.035),0.067,0.080,"rubber")
		cylinder(origin+Vector3(0,0.29,0.035),0.057,0.003,"iron")
		for index in 7:
			var angle := index*TAU/7
			oval(origin+Vector3(cos(angle)*0.048,0.042+(index%3)*0.012,-0.07+sin(angle)*0.085),Vector3(0.060,0.030,0.070),"mud")
		for z in [-0.13,-0.07,0,0.06]: box(origin+Vector3(0,0.009,z),Vector3(0.13,0.017,0.014),"rubber")
		box(origin+Vector3(0,0.31,0.112),Vector3(0.027,0.067,0.012),"boot")

func planter() -> void:
	lathe([Vector2(0,0.01),Vector2(0.10,0.01),Vector2(0.15,0.28),Vector2(0.155,0.31),Vector2(0.14,0.31),Vector2(0.13,0.27),Vector2(0.085,0.035),Vector2(0,0.035)],"terra")
	hoop(Vector3(0,0.292,0),0.142,0.16,"terra")
	cylinder(Vector3(0,0.266,0),0.128,0.008,"soil")
	tube(PackedVector3Array([Vector3(0,0.27,0),Vector3(0.015,0.48,0),Vector3(-0.01,0.68,0.015),Vector3(0.01,0.81,0)]),0.006,"leaf_dark",6)
	var colours := ["leaf","leaf_light","leaf_dark"]
	for index in 22:
		var angle := index*2.40
		var y := 0.32+index*0.020
		var reach := 0.22-absf(index-9)*0.006
		var root := Vector3(0.01,y,0)
		var end := root+Vector3(cos(angle)*reach,0.04+(index%3)*0.025,sin(angle)*reach)
		var start := root.lerp(end,0.30)
		rod(root,start,0.0025,"leaf_dark")
		leaf(start,end,0.042+(index%3)*0.006,colours[index%3])
	collision.append(AABB(Vector3(-0.16,0,-0.16),Vector3(0.32,0.31,0.32)))

func leaf(start: Vector3, end: Vector3, width: float, material: String) -> void:
	var side := (end-start).cross(Vector3.UP).normalized()*width
	var middle := start.lerp(end,0.46)
	var ridge := middle+Vector3.UP*0.018
	var vertices := [start,middle+side,end,middle-side,ridge]
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for corner in [0,1,4,1,2,4,2,3,4,3,0,4]: surface.set_uv(Vector2(vertices[corner].x,vertices[corner].z)); surface.add_vertex(vertices[corner])
	surface.generate_normals(); surface.index(); append(surface.commit(),Transform3D.IDENTITY,material)

func watering_can() -> void:
	lathe([Vector2(0,0.008),Vector2(0.135,0.008),Vector2(0.15,0.05),Vector2(0.15,0.23),Vector2(0.13,0.27),Vector2(0.07,0.27),Vector2(0.07,0.258),Vector2(0.12,0.255),Vector2(0.138,0.225),Vector2(0.138,0.035),Vector2(0,0.025)],"teal")
	hoop(Vector3(0,0.035,0),0.143,0.151,"steel")
	hoop(Vector3(0,0.265,0),0.068,0.076,"steel")
	tube(PackedVector3Array([Vector3(0.11,0.10,0),Vector3(0.21,0.14,0),Vector3(0.31,0.24,0),Vector3(0.39,0.29,0)]),0.017,"teal")
	var axis := Vector3(0.85,0.52,0).normalized()
	cylinder(Vector3(0.401,0.297,0),0.043,0.030,"teal",axis)
	cylinder(Vector3(0.415,0.306,0),0.039,0.003,"steel",axis)
	var face := Basis(Quaternion(Vector3.UP,axis))
	for index in 12:
		var angle := index*TAU/12
		cylinder(Vector3(0.417,0.307,0)+face*Vector3(cos(angle)*0.026,0,sin(angle)*0.026),0.0022,0.002,"iron",axis)
	var handle := PackedVector3Array()
	for index in 21:
		var angle := PI-index*PI/20
		handle.append(Vector3(cos(angle)*0.12,0.27+sin(angle)*0.16,0))
	tube(handle,0.010,"teal")
	tube(PackedVector3Array([Vector3(-0.12,0.23,0),Vector3(-0.23,0.25,0),Vector3(-0.26,0.18,0),Vector3(-0.22,0.085,0),Vector3(-0.12,0.07,0)]),0.012,"teal")
