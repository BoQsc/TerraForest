# SPDX-License-Identifier: 0BSD
extends "res://addons/structures/packs/homestead_02/author.gd"
## Original workshop geometry using the project's 0BSD offline mesh helpers.

func _init() -> void:
	super()
	for material: Material in materials.values(): material.resource_name=material.resource_name.replace("Homestead 02","Homestead 04")
	materials.teal.cull_mode=BaseMaterial3D.CULL_DISABLED
	var steel := StandardMaterial3D.new(); steel.resource_name="Homestead 04 / dull steel"; steel.albedo_color=Color("9aa5a5"); steel.metallic=0.72; steel.roughness=0.48; steel.cull_mode=BaseMaterial3D.CULL_DISABLED; materials.steel=steel
	var rope := StandardMaterial3D.new(); rope.resource_name="Homestead 04 / twisted fibre"; rope.albedo_color=Color("b49a69"); rope.roughness=0.95; rope.albedo_texture=texture(true); rope.cull_mode=BaseMaterial3D.CULL_DISABLED; materials.rope=rope
	var rubber := StandardMaterial3D.new(); rubber.resource_name="Homestead 04 / rubber"; rubber.albedo_color=Color("293337"); rubber.roughness=0.80; rubber.cull_mode=BaseMaterial3D.CULL_DISABLED; materials.rubber=rubber

func strut(start: Vector3, end: Vector3, width: float, depth: float, material: String="wood") -> void:
	var basis := Basis(Quaternion(Vector3.UP,(end-start).normalized()))
	box((start+end)*0.5,Vector3(width,start.distance_to(end),depth),material,true,basis)

func tube(points: PackedVector3Array, radius: float, material: String, sides: int=8) -> void:
	var rings: Array[PackedVector3Array]=[]
	var normals: Array[PackedVector3Array]=[]
	for index in points.size():
		var tangent := (points[mini(index+1,points.size()-1)]-points[maxi(index-1,0)]).normalized()
		var side := tangent.cross(Vector3.UP)
		if side.length_squared()<0.001: side=tangent.cross(Vector3.RIGHT)
		side=side.normalized()
		var up := side.cross(tangent).normalized()
		var ring := PackedVector3Array(); var normal_ring := PackedVector3Array()
		for segment in sides:
			var normal := side*cos(segment*TAU/sides)+up*sin(segment*TAU/sides)
			ring.append(points[index]+normal*radius); normal_ring.append(normal)
		rings.append(ring); normals.append(normal_ring)
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in points.size()-1:
		for segment in sides:
			var next := (segment+1)%sides
			var vertices := [rings[index][segment],rings[index+1][segment],rings[index+1][next],rings[index][next]]
			var radial := [normals[index][segment],normals[index+1][segment],normals[index+1][next],normals[index][next]]
			for corner in [0,1,2,0,2,3]: surface.set_normal(radial[corner]); surface.set_uv(Vector2(float(segment)/sides,float(index)*0.04)); surface.add_vertex(vertices[corner])
	surface.index(); append(surface.commit(),Transform3D.IDENTITY,material)
	sphere(points[0],radius,material); sphere(points[points.size()-1],radius,material)

func build(slug: String) -> ArrayMesh:
	surfaces.clear(); collision.clear(); wall_points.clear()
	match slug:
		"workbench": workbench()
		"vise": vise()
		"tool_board": tool_board()
		"toolbox": toolbox()
		"sawhorse": sawhorse()
		"plank_stack": plank_stack()
		"paint_tin": paint_tin()
		"rope": rope_coil()
		"cable_spool": cable_spool()
		"handcart": handcart()
	var raw := ArrayMesh.new()
	for surface: SurfaceTool in surfaces.values(): surface.index(); surface.commit(raw)
	if slug in ["rope","cable_spool","plank_stack"]: collision.assign([raw.get_aabb()])
	var pose := Transform3D(Basis.IDENTITY,Vector3(0,-raw.get_aabb().position.y,0))
	var mesh := ArrayMesh.new()
	for index in raw.get_surface_count():
		var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); surface.set_material(raw.surface_get_material(index)); surface.append_from(raw,index,pose); surface.commit(mesh)
	for index in collision.size(): collision[index]=pose*collision[index]
	for index in wall_points.size(): wall_points[index]=pose*wall_points[index]
	mesh.resource_name="Homestead 04 / "+slug
	mesh.set_meta("pack_id","terraforest.homestead_04"); mesh.set_meta("collision_boxes",collision.duplicate()); mesh.set_meta("authored_size",mesh.get_aabb().size)
	if not wall_points.is_empty(): mesh.set_meta("wall_support_points",wall_points)
	return mesh

func workbench() -> void:
	for x in [-0.72,0.72]:
		for z in [-0.27,0.27]: box(Vector3(x,0.40,z),Vector3(0.11,0.80,0.11),"wood",true)
	for z in [-0.29,0.29]: box(Vector3(0,0.69,z),Vector3(1.55,0.16,0.055),"wood",true)
	for x in [-0.72,0.72]: box(Vector3(x,0.22,0),Vector3(0.08,0.10,0.59),"wood",true)
	box(Vector3(0,0.23,0),Vector3(1.48,0.055,0.48),"wood",true)
	for index in 6: box(Vector3(-0.75+index*0.30,0.845,0),Vector3(0.294,0.10,0.76),"edge",true)
	for x in [-0.47,0,0.47]:
		box(Vector3(x,0.675,-0.325),Vector3(0.44,0.17,0.055),"teal")
		box(Vector3(x,0.675,-0.361),Vector3(0.14,0.023,0.026),"iron")
	for x in [-0.72,0.72]:
		for y in [0.28,0.70]: cylinder(Vector3(x,y,-0.331),0.012,0.008,"steel",Vector3.FORWARD)

func vise() -> void:
	cylinder(Vector3(0,0.026,0),0.12,0.052,"iron")
	box(Vector3(0,0.10,0.015),Vector3(0.16,0.12,0.19),"teal",true)
	for z in [-0.09,0.11]:
		box(Vector3(0,0.21,z),Vector3(0.21,0.10,0.055),"teal",true)
		box(Vector3(0,0.255,z),Vector3(0.22,0.024,0.058),"steel")
		for index in 10: box(Vector3(-0.092+index*0.020,0.27,z),Vector3(0.006,0.005,0.055),"iron")
	rod(Vector3(0,0.125,-0.30),Vector3(0,0.125,0.13),0.014,"steel")
	for index in 15: hoop(Vector3(0,0.125,-0.27+index*0.021),0.014,0.019,"steel",Basis(Vector3.RIGHT,PI*0.5))
	rod(Vector3(-0.12,0.125,-0.315),Vector3(0.12,0.125,-0.315),0.009,"steel")
	for x in [-0.125,0.125]: sphere(Vector3(x,0.125,-0.315),0.016,"rust")
	for x in [-0.075,0.075]: cylinder(Vector3(x,0.057,0.02),0.012,0.014,"brass")
	collision.append(AABB(Vector3(-0.12,0,-0.12),Vector3(0.24,0.06,0.24)))
	collision.append(AABB(Vector3(-0.14,0.10,-0.335),Vector3(0.28,0.05,0.45)))

func tool_board() -> void:
	box(Vector3(0,0.43,0),Vector3(0.96,0.78,0.04),"teal",true)
	for x in [-0.49,0.49]: box(Vector3(x,0.43,-0.01),Vector3(0.05,0.84,0.06),"edge")
	for y in [0.035,0.825]: box(Vector3(0,y,-0.01),Vector3(1.02,0.05,0.06),"edge")
	for column in 10:
		for row in 7: cylinder(Vector3(-0.405+column*0.09,0.14+row*0.09,-0.022),0.005,0.003,"iron",Vector3.FORWARD)
	# Four original decorative tools, authored here rather than copied from held art.
	polygon(PackedVector3Array([Vector3(-0.41,0.22,-0.035),Vector3(-0.18,0.28,-0.035),Vector3(-0.18,0.61,-0.035),Vector3(-0.28,0.61,-0.035)]),"steel")
	for index in 13:
		var y := 0.24+index*0.025
		polygon(PackedVector3Array([Vector3(-0.40+(y-0.24)*0.40,y,-0.036),Vector3(-0.42+(y-0.24)*0.40,y+0.014,-0.036),Vector3(-0.39+(y-0.24)*0.40,y+0.023,-0.036)]),"steel")
	hoop(Vector3(-0.22,0.66,-0.045),0.034,0.060,"wood",Basis(Vector3.RIGHT,PI*0.5))
	rod(Vector3(-0.04,0.25,-0.05),Vector3(-0.04,0.64,-0.05),0.017,"wood")
	box(Vector3(-0.03,0.64,-0.05),Vector3(0.19,0.065,0.06),"iron")
	rod(Vector3(0.18,0.27,-0.05),Vector3(0.18,0.61,-0.05),0.016,"steel")
	hoop(Vector3(0.18,0.26,-0.05),0.022,0.040,"steel",Basis(Vector3.RIGHT,PI*0.5))
	for x in [0.145,0.215]: rod(Vector3(0.18,0.60,-0.05),Vector3(x,0.66,-0.05),0.012,"steel")
	rod(Vector3(0.35,0.23,-0.05),Vector3(0.35,0.50,-0.05),0.006,"steel")
	cylinder(Vector3(0.35,0.57,-0.05),0.023,0.14,"rust")
	for x in [-0.22,-0.04,0.18,0.35]: rod(Vector3(x,0.69,-0.025),Vector3(x,0.69,-0.077),0.008,"brass")
	wall_points=PackedVector3Array([Vector3(-0.40,0.13,0.02),Vector3(0.40,0.13,0.02),Vector3(-0.40,0.73,0.02),Vector3(0.40,0.73,0.02)])

func toolbox() -> void:
	box(Vector3(0,0.12,0),Vector3(0.48,0.20,0.26),"teal",true)
	box(Vector3(0,0.245,0),Vector3(0.49,0.06,0.27),"teal",true)
	for z in [-0.10,0.10]: box(Vector3(0,0.275,z),Vector3(0.49,0.025,0.10),"teal",false,Basis(Vector3.RIGHT,0.45 if z<0 else -0.45))
	for x in [-0.21,0.21]: box(Vector3(x,0.02,0),Vector3(0.045,0.04,0.23),"iron")
	for x in [-0.08,0.08]: rod(Vector3(x,0.28,0),Vector3(x,0.37,0),0.012,"iron")
	rod(Vector3(-0.08,0.37,0),Vector3(0.08,0.37,0),0.020,"rubber")
	for x in [-0.14,0.14]:
		box(Vector3(x,0.215,-0.137),Vector3(0.033,0.07,0.014),"steel")
		cylinder(Vector3(x,0.205,-0.149),0.008,0.008,"brass",Vector3.FORWARD)
	box(Vector3(0,0.12,-0.134),Vector3(0.16,0.045,0.008),"rust")

func sawhorse() -> void:
	box(Vector3(0,0.77,0),Vector3(1.23,0.11,0.14),"edge",true)
	for x in [-0.44,0.44]:
		for z in [-0.31,0.31]: strut(Vector3(x,0.025,z),Vector3(x,0.73,z*0.14),0.075,0.075)
		box(Vector3(x,0.29,0),Vector3(0.06,0.06,0.45),"wood",true)
	box(Vector3(0,0.31,0),Vector3(0.91,0.06,0.06),"wood",true)

func plank_stack() -> void:
	for x in [-0.46,0.46]: box(Vector3(x,0.023,0),Vector3(0.08,0.046,0.59),"wood")
	for level in 2:
		for row in 3: box(Vector3(level*0.04,0.071+level*0.05,-0.19+row*0.19),Vector3(1.46-level*0.10,0.045,0.17),"edge" if row%2==0 else "wood")
	for row in 2: box(Vector3(0.10,0.171,-0.13+row*0.22),Vector3(1.16,0.045,0.17),"edge",false,Basis(Vector3.UP,0.055))

func paint_tin() -> void:
	lathe([Vector2(0,0),Vector2(0.10,0),Vector2(0.11,0.015),Vector2(0.11,0.21),Vector2(0.103,0.22),Vector2(0.098,0.21),Vector2(0.098,0.02),Vector2(0,0.012)],"teal")
	hoop(Vector3(0,0.215,0),0.102,0.115,"steel")
	cylinder(Vector3(0,0.177,0),0.099,0.005,"rust")
	var handle := PackedVector3Array()
	for index in 25:
		var angle := index*PI/24.0
		handle.append(Vector3(cos(angle)*0.115,0.19+sin(angle)*0.16,0.012))
	tube(handle,0.004,"iron",6)
	box(Vector3(0,0.105,-0.111),Vector3(0.12,0.08,0.003),"linen")
	box(Vector3(0,0.105,-0.114),Vector3(0.075,0.014,0.003),"rust")
	rod(Vector3(0.02,0.24,-0.04),Vector3(0.25,0.24,-0.04),0.016,"wood")
	box(Vector3(-0.012,0.24,-0.04),Vector3(0.060,0.035,0.055),"steel")
	box(Vector3(-0.075,0.237,-0.04),Vector3(0.075,0.028,0.055),"rope")
	box(Vector3(-0.107,0.237,-0.04),Vector3(0.015,0.030,0.056),"rust")
	collision.append(AABB(Vector3(-0.115,0,-0.115),Vector3(0.23,0.22,0.23)))
	collision.append(AABB(Vector3(-0.12,0.22,-0.075),Vector3(0.39,0.04,0.07)))

func rope_coil() -> void:
	var points := PackedVector3Array()
	for index in 301:
		var t := index/300.0; var angle := t*TAU*5.5
		var radius := 0.055+t*0.235
		points.append(Vector3(cos(angle)*radius,0.014,sin(angle)*radius))
	points.append(Vector3(-0.34,0.014,-0.03)); points.append(Vector3(-0.39,0.014,-0.14)); points.append(Vector3(-0.30,0.014,-0.23))
	tube(points,0.012,"rope")

func cable_spool() -> void:
	for x in [-0.225,0.225]:
		cylinder(Vector3(x,0.32,0),0.31,0.035,"edge",Vector3.RIGHT)
		cylinder(Vector3(x*1.085,0.32,0),0.042,0.003,"iron",Vector3.RIGHT)
		for index in 4:
			var angle := index*TAU/4
			cylinder(Vector3(x*1.09,0.32+cos(angle)*0.18,sin(angle)*0.18),0.012,0.005,"steel",Vector3.RIGHT)
	cylinder(Vector3(0,0.32,0),0.217,0.42,"rubber",Vector3.RIGHT)
	var winding := PackedVector3Array()
	for index in 337:
		var t := index/336.0; var angle := t*TAU*14
		winding.append(Vector3(-0.205+t*0.41,0.32+cos(angle)*0.226,sin(angle)*0.226))
	tube(winding,0.012,"rubber")
	tube(PackedVector3Array([Vector3(0.20,0.54,0),Vector3(0.29,0.25,-0.16),Vector3(0.29,0.025,-0.35),Vector3(0.15,0.025,-0.39)]),0.012,"rubber")

func handcart() -> void:
	for row in 7: box(Vector3(-0.30+row*0.10,0.43,0),Vector3(0.094,0.05,1.0),"edge")
	for z in [-0.38,0.38]: box(Vector3(0,0.39,z),Vector3(0.76,0.08,0.08),"iron")
	for x in [-0.35,0.35]:
		for z in [-0.46,0.46]: box(Vector3(x,0.59,z),Vector3(0.05,0.32,0.05),"wood")
		for y in [0.52,0.68]: box(Vector3(x,y,0),Vector3(0.045,0.10,1.04),"wood",true)
	for y in [0.52,0.68]: box(Vector3(0,y,-0.50),Vector3(0.74,0.10,0.04),"edge",true)
	rod(Vector3(-0.49,0.235,0),Vector3(0.49,0.235,0),0.022,"iron")
	for x in [-0.44,0.44]:
		hoop(Vector3(x,0.235,0),0.19,0.235,"rubber",Basis(Vector3.FORWARD,PI*0.5))
		hoop(Vector3(x,0.235,0),0.17,0.19,"teal",Basis(Vector3.FORWARD,PI*0.5))
		cylinder(Vector3(x,0.235,0),0.045,0.09,"steel",Vector3.RIGHT)
		for index in 6:
			var angle := index*TAU/6
			rod(Vector3(x,0.235,0),Vector3(x,0.235+cos(angle)*0.17,sin(angle)*0.17),0.008,"iron")
		collision.append(AABB(Vector3(x-0.045,0,-0.235),Vector3(0.09,0.47,0.47)))
	for x in [-0.27,0.27]:
		strut(Vector3(x,0.05,0.46),Vector3(x,0.40,0.40),0.035,0.035,"iron")
		rod(Vector3(x,0.40,0.30),Vector3(x,0.66,1.0),0.022,"iron")
		rod(Vector3(x,0.62,0.88),Vector3(x,0.68,1.06),0.027,"rubber")
		collision.append(AABB(Vector3(x-0.03,0.40,0.31),Vector3(0.06,0.31,0.78)))
	collision.append(AABB(Vector3(-0.37,0.39,-0.51),Vector3(0.74,0.07,1.02)))
