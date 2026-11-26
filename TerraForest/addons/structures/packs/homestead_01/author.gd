# SPDX-License-Identifier: 0BSD
extends RefCounted
## Editable original geometry. Offline only; no per-object runtime scripts.
const Catalog = preload("res://addons/structures/packs/homestead_01/catalog.gd")
var materials: Dictionary = {}
var surfaces: Dictionary = {}
var collision: Array[AABB] = []

func _init() -> void:
	var palette := {"wood":"70503c","edge":"b28a58","teal":"527975","cream":"ded4b8","fabric":"648180","iron":"303a3d","brass":"b79b62","paper":"cbbf9e","red":"8a4c42","navy":"43576b"}
	for label: String in palette:
		var material := StandardMaterial3D.new()
		material.resource_name = "Homestead 01 / " + label
		material.albedo_color = Color(palette[label])
		material.roughness = 0.86 if label not in ["iron","brass","cream"] else 0.48
		material.metallic = 0.65 if label in ["iron","brass"] else 0.0
		if label in ["wood","edge","teal","fabric"]: material.albedo_texture = texture(label == "fabric")
		materials[label] = material

func texture(fabric: bool) -> ImageTexture:
	var pixels := Image.create(128,128,false,Image.FORMAT_RGB8)
	var random := RandomNumberGenerator.new(); random.seed = 170301
	for y in 128:
		for x in 128:
			var value: float
			if fabric: value = 0.88 + 0.065*float((x+y)%2) + random.randf()*0.035
			else: value = 0.85 + 0.07*sin(x*0.52 + 1.3*sin(y*0.07)) + 0.04*sin(x*1.8+y*0.013) + random.randf()*0.035
			pixels.set_pixel(x,y,Color(value,value,value))
	return ImageTexture.create_from_image(pixels)

func box(center: Vector3, size: Vector3, material: String, solid: bool = true, turn: float = 0.0) -> void:
	var mesh := BoxMesh.new(); mesh.size = size
	append(mesh, Transform3D(Basis(Vector3.UP,turn),center), material)
	if solid: collision.append(Transform3D(Basis(Vector3.UP,turn),center)*AABB(-size*0.5,size))

func append(mesh: Mesh, pose: Transform3D, material: String) -> void:
	if not surfaces.has(material):
		var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); surface.set_material(materials[material]); surfaces[material] = surface
	surfaces[material].append_from(mesh,0,pose)

func cylinder(center: Vector3, radius: float, height: float, material: String, direction: Vector3 = Vector3.UP) -> void:
	var mesh := CylinderMesh.new(); mesh.top_radius = radius; mesh.bottom_radius = radius; mesh.height = height; mesh.radial_segments = 16; mesh.rings = 1
	var basis := Basis.IDENTITY
	if not direction.is_equal_approx(Vector3.UP): basis = Basis(Quaternion(Vector3.UP,direction.normalized()))
	append(mesh,Transform3D(basis,center),material)

func feet(width: float, depth: float, height: float, material: String = "wood") -> void:
	for x in [-width*0.5+0.07,width*0.5-0.07]:
		for z in [-depth*0.5+0.07,depth*0.5-0.07]: box(Vector3(x,height*0.5,z),Vector3(0.1,height,0.1),material)

func knob(center: Vector3) -> void:
	cylinder(center,0.023,0.045,"brass",Vector3.FORWARD)

func panel(center: Vector3, size: Vector3, material: String) -> void:
	box(center,size,material)
	box(center+Vector3(0,0,-size.z*0.5-0.006),Vector3(size.x-0.075,size.y-0.075,0.012),"wood",false)

func build(slug: String) -> ArrayMesh:
	surfaces.clear(); collision.clear()
	match slug:
		"bed":
			feet(1.46,2.16,0.31)
			box(Vector3(0,0.29,0),Vector3(1.46,0.18,2.16),"wood")
			box(Vector3(0,0.49,0),Vector3(1.36,0.22,2.04),"cream")
			box(Vector3(0,0.615,-0.27),Vector3(1.39,0.055,1.47),"fabric",false)
			box(Vector3(0,0.65,0.68),Vector3(0.95,0.13,0.42),"cream",false)
			box(Vector3(0,0.70,1.035),Vector3(1.52,0.83,0.11),"wood")
			box(Vector3(0,1.13,1.035),Vector3(1.58,0.07,0.15),"edge",false)
			box(Vector3(0,0.44,-1.035),Vector3(1.52,0.43,0.11),"wood")
			for x in [-0.73,0.73]: box(Vector3(x,0.75,1.035),Vector3(0.09,0.96,0.14),"edge",false)
		"nightstand":
			feet(0.54,0.46,0.19)
			box(Vector3(0,0.34,0.025),Vector3(0.5,0.34,0.4),"wood")
			box(Vector3(0,0.54,0),Vector3(0.58,0.07,0.5),"edge")
			panel(Vector3(0,0.42,-0.19),Vector3(0.43,0.15,0.035),"teal"); knob(Vector3(0,0.42,-0.23))
			box(Vector3(0,0.21,-0.22),Vector3(0.44,0.025,0.035),"edge",false)
		"wardrobe":
			feet(1.12,0.56,0.16)
			box(Vector3(0,1.04,0.025),Vector3(1.10,1.80,0.52),"wood")
			for x in [-0.265,0.265]: panel(Vector3(x,1.05,-0.255),Vector3(0.51,1.66,0.05),"teal"); knob(Vector3(x*0.18,1.03,-0.30))
			box(Vector3(0,1.98,0),Vector3(1.22,0.10,0.64),"edge")
			box(Vector3(0,0.18,0),Vector3(1.18,0.08,0.60),"edge",false)
		"counter":
			feet(1.2,0.65,0.18)
			box(Vector3(0,0.47,0.02),Vector3(1.14,0.64,0.59),"wood")
			box(Vector3(0,0.85,0),Vector3(1.24,0.10,0.69),"edge")
			for x in [-0.28,0.28]: panel(Vector3(x,0.46,-0.295),Vector3(0.53,0.55,0.04),"teal"); knob(Vector3(x*0.40,0.62,-0.34))
		"cupboard":
			feet(0.86,0.42,0.16)
			box(Vector3(0,0.57,0),Vector3(0.83,0.88,0.4),"wood")
			for x in [-0.20,0.20]: panel(Vector3(x,0.57,-0.21),Vector3(0.38,0.76,0.035),"teal"); knob(Vector3(x*0.22,0.61,-0.25))
			box(Vector3(0,1.06,0),Vector3(0.94,0.09,0.49),"edge")
		"sink": sink()
		"stove":
			feet(0.73,0.62,0.17,"iron")
			box(Vector3(0,0.49,0),Vector3(0.70,0.66,0.58),"iron")
			box(Vector3(0,0.85,0),Vector3(0.78,0.07,0.66),"cream")
			for x in [-0.19,0.19]:
				for z in [-0.16,0.16]: cylinder(Vector3(x,0.894,z),0.12,0.018,"iron"); cylinder(Vector3(x,0.907,z),0.068,0.012,"iron")
			panel(Vector3(0,0.46,-0.303),Vector3(0.54,0.43,0.025),"iron")
			box(Vector3(0,0.48,-0.323),Vector3(0.41,0.27,0.015),"navy",false)
			box(Vector3(0,0.67,-0.352),Vector3(0.44,0.035,0.045),"brass",false)
			for x in [-0.25,0.25]: knob(Vector3(x,0.77,-0.33))
			box(Vector3(0,0.98,0.28),Vector3(0.75,0.20,0.06),"cream")
		"sofa":
			feet(1.88,0.82,0.18)
			box(Vector3(0,0.30,0),Vector3(1.80,0.28,0.80),"wood")
			box(Vector3(0,0.68,0.32),Vector3(1.94,0.65,0.19),"fabric")
			for x in [-0.91,0.91]: box(Vector3(x,0.52,0),Vector3(0.20,0.57,0.88),"fabric")
			for x in [-0.405,0.405]:
				box(Vector3(x,0.49,-0.06),Vector3(0.79,0.20,0.64),"fabric")
				box(Vector3(x,0.78,0.20),Vector3(0.77,0.38,0.10),"teal",false)
			box(Vector3(-0.58,0.63,-0.03),Vector3(0.30,0.08,0.46),"cream",false,0.22)
		"books":
			for index in 4:
				var height := 0.04 + index*0.055
				var width := 0.29 - index*0.015
				var turn: float = [-0.10,0.05,-0.04,0.13][index]
				var color: String = ["red","navy","teal","wood"][index]
				box(Vector3(0,height,0),Vector3(width,0.035,0.20),"paper",false,turn)
				for dy in [-0.022,0.022]: box(Vector3(0,height+dy,0),Vector3(width+0.012,0.008,0.213),color,false,turn)
			collision.append(AABB(Vector3(-0.17,0.01,-0.13),Vector3(0.34,0.22,0.26)))
		"mug": mug()
	var result := ArrayMesh.new()
	for surface: SurfaceTool in surfaces.values(): surface.index(); surface.commit(result)
	result.resource_name = "Homestead 01 / " + slug
	result.set_meta("pack_id",Catalog.ID)
	result.set_meta("collision_boxes",collision.duplicate())
	result.set_meta("authored_size",result.get_aabb().size)
	return result

func sink() -> void:
	feet(0.88,0.59,0.72)
	box(Vector3(0,0.18,0),Vector3(0.78,0.055,0.48),"wood")
	box(Vector3(0,0.79,0),Vector3(0.90,0.09,0.60),"cream")
	# Open basin: floor and four rims preserve the visible hollow.
	box(Vector3(0,0.85,-0.015),Vector3(0.68,0.035,0.41),"iron",false)
	for x in [-0.39,0.39]: box(Vector3(x,0.91,0),Vector3(0.10,0.20,0.60),"cream")
	for z in [-0.255,0.255]: box(Vector3(0,0.91,z),Vector3(0.70,0.20,0.09),"cream")
	cylinder(Vector3(0,1.08,0.22),0.022,0.23,"brass")
	cylinder(Vector3(0,1.19,0.12),0.022,0.20,"brass",Vector3.FORWARD)
	cylinder(Vector3(0,1.16,0.025),0.024,0.08,"brass")
	cylinder(Vector3(0,0.87,-0.015),0.035,0.008,"brass")
	for x in [-0.12,0.12]: cylinder(Vector3(x,1.015,0.23),0.035,0.035,"brass")

func mug() -> void:
	# Revolved annular wall: open mouth, interior wall and closed base.
	var mesh := SurfaceTool.new(); mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	var profile := [Vector2(0,0.008),Vector2(0.054,0.008),Vector2(0.060,0.02),Vector2(0.063,0.125),Vector2(0.055,0.125),Vector2(0.052,0.020),Vector2(0,0.020)]
	for segment in 24:
		var a := segment*TAU/24.0; var b := (segment+1)*TAU/24.0
		for index in profile.size()-1:
			var p: Vector2 = profile[index]; var q: Vector2 = profile[index+1]
			var vertices := [Vector3(p.x*cos(a),p.y,p.x*sin(a)),Vector3(p.x*cos(b),p.y,p.x*sin(b)),Vector3(q.x*cos(b),q.y,q.x*sin(b)),Vector3(q.x*cos(a),q.y,q.x*sin(a))]
			for corner in [0,2,1,0,3,2]: mesh.add_vertex(vertices[corner])
	mesh.generate_normals(); mesh.index(); append(mesh.commit(),Transform3D.IDENTITY,"cream")
	var rim := TorusMesh.new(); rim.inner_radius=0.054; rim.outer_radius=0.065; rim.rings=24; rim.ring_segments=8
	append(rim,Transform3D(Basis.IDENTITY,Vector3(0,0.124,0)),"navy")
	var handle := TorusMesh.new(); handle.inner_radius=0.028; handle.outer_radius=0.040; handle.rings=16; handle.ring_segments=8
	append(handle,Transform3D(Basis(Vector3.RIGHT,PI*0.5),Vector3(0.078,0.071,0)),"cream")
	collision.append(AABB(Vector3(-0.063,0,-0.063),Vector3(0.181,0.13,0.126)))
