# SPDX-License-Identifier: 0BSD
extends "res://addons/structures/packs/homestead_04/author.gd"
## Original kitchen geometry using the project's 0BSD offline mesh/tube helpers.

func _init() -> void:
	super()
	for material: Material in materials.values(): material.resource_name=material.resource_name.replace("Homestead 04","Homestead 05")
	materials.wood.cull_mode=BaseMaterial3D.CULL_DISABLED
	materials.teal.cull_mode=BaseMaterial3D.CULL_DISABLED
	materials.ceramic.albedo_color=Color("e5ddc7")
	materials.glass.albedo_color=Color(0.70,0.86,0.79,0.27); materials.glass.roughness=0.16
	var palette := {"copper":"b46d43","beet":"8a3547","preserve":"d9a258","pickle":"688249","sacking":"b09a70","grain":"d5bc80"}
	for label: String in palette:
		var material := StandardMaterial3D.new(); material.resource_name="Homestead 05 / "+label; material.albedo_color=Color(palette[label]); material.roughness=0.78; material.cull_mode=BaseMaterial3D.CULL_DISABLED
		if label=="copper": material.metallic=0.78; material.roughness=0.40
		if label=="sacking": material.albedo_texture=texture(true)
		materials[label]=material

func shaped_lathe(profile: Array[Vector2], material: String, pose: Transform3D) -> void:
	var previous := surfaces
	surfaces={}; lathe(profile,material)
	var surface: SurfaceTool=surfaces[material]
	var mesh := surface.commit()
	surfaces=previous; append(mesh,pose,material)

func build(slug: String) -> ArrayMesh:
	surfaces.clear(); collision.clear(); wall_points.clear()
	match slug:
		"refrigerator": refrigerator()
		"kettle": kettle()
		"cooking_pot": cooking_pot()
		"frying_pan": frying_pan()
		"cutting_board": cutting_board()
		"utensil_rail": utensil_rail()
		"plate_rack": plate_rack()
		"preserve_jars": preserve_jars()
		"bread_bin": bread_bin()
		"grain_sack": grain_sack()
	var raw := ArrayMesh.new()
	for surface: SurfaceTool in surfaces.values(): surface.index(); surface.commit(raw)
	if slug in ["kettle","frying_pan","cutting_board","preserve_jars","bread_bin","grain_sack"]: collision.assign([raw.get_aabb()])
	var pose := Transform3D(Basis.IDENTITY,Vector3(0,-raw.get_aabb().position.y,0))
	var mesh := ArrayMesh.new()
	for index in raw.get_surface_count():
		var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); surface.set_material(raw.surface_get_material(index)); surface.append_from(raw,index,pose); surface.commit(mesh)
	for index in collision.size(): collision[index]=pose*collision[index]
	for index in wall_points.size(): wall_points[index]=pose*wall_points[index]
	mesh.resource_name="Homestead 05 / "+slug
	mesh.set_meta("pack_id","terraforest.homestead_05"); mesh.set_meta("collision_boxes",collision.duplicate()); mesh.set_meta("authored_size",mesh.get_aabb().size)
	if not wall_points.is_empty(): mesh.set_meta("wall_support_points",wall_points)
	return mesh

func refrigerator() -> void:
	for x in [-0.25,0.25]:
		for z in [-0.22,0.22]: box(Vector3(x,0.035,z),Vector3(0.08,0.07,0.08),"iron")
	box(Vector3(0,0.79,0),Vector3(0.58,1.42,0.62),"teal")
	box(Vector3(0,0.79,0),Vector3(0.66,1.42,0.54),"teal",true)
	for x in [-0.29,0.29]:
		for z in [-0.27,0.27]: cylinder(Vector3(x,0.79,z),0.04,1.42,"teal")
	box(Vector3(0,0.58,-0.327),Vector3(0.60,0.87,0.055),"ceramic",true)
	box(Vector3(0,1.265,-0.327),Vector3(0.60,0.43,0.055),"ceramic",true)
	for y in [0.73,1.27]:
		rod(Vector3(-0.22,y-0.09,-0.365),Vector3(-0.22,y+0.09,-0.365),0.015,"brass")
		for dy in [-0.075,0.075]: rod(Vector3(-0.22,y+dy,-0.35),Vector3(-0.22,y+dy,-0.38),0.012,"brass")
	box(Vector3(0.18,1.39,-0.359),Vector3(0.12,0.024,0.008),"steel")
	box(Vector3(0,0.115,-0.318),Vector3(0.56,0.07,0.025),"iron")
	for index in 8: box(Vector3(-0.21+index*0.06,0.115,-0.333),Vector3(0.028,0.035,0.005),"steel")

func kettle() -> void:
	lathe([Vector2(0,0),Vector2(0.10,0),Vector2(0.145,0.055),Vector2(0.15,0.15),Vector2(0.115,0.23),Vector2(0.082,0.25),Vector2(0.073,0.25),Vector2(0.105,0.22),Vector2(0.14,0.15),Vector2(0.13,0.06),Vector2(0.085,0.018),Vector2(0,0.018)],"copper")
	lathe([Vector2(0,0.257),Vector2(0.08,0.257),Vector2(0.09,0.266),Vector2(0.07,0.28),Vector2(0,0.288)],"copper")
	sphere(Vector3(0,0.305,0),0.022,"wood")
	var spout := PackedVector3Array([Vector3(0.12,0.12,0),Vector3(0.19,0.145,0),Vector3(0.22,0.205,0),Vector3(0.265,0.235,0)])
	tube(spout,0.025,"copper")
	cylinder(Vector3(0.282,0.246,0),0.016,0.003,"iron",Vector3(0.045,0.03,0))
	var handle := PackedVector3Array()
	for index in 25:
		var angle := index*PI/24.0
		handle.append(Vector3(0,0.19+sin(angle)*0.24,cos(angle)*0.16))
	tube(handle,0.017,"wood")
	for z in [-0.155,0.155]: sphere(Vector3(0,0.19,z),0.025,"iron")

func cooking_pot() -> void:
	var center := Vector3(-0.075,0,0)
	lathe([Vector2(0,0),Vector2(0.145,0),Vector2(0.17,0.025),Vector2(0.17,0.195),Vector2(0.158,0.205),Vector2(0.155,0.035),Vector2(0.135,0.02),Vector2(0,0.02)],"copper",center)
	hoop(center+Vector3(0,0.195,0),0.157,0.177,"steel")
	for x in [-0.275,0.125]: hoop(Vector3(x,0.14,0),0.026,0.043,"iron",Basis(Vector3.FORWARD,PI*0.5))
	rod(Vector3(-0.245,0.14,0),Vector3(-0.275,0.14,0),0.010,"iron")
	rod(Vector3(0.095,0.14,0),Vector3(0.125,0.14,0),0.010,"iron")
	var pose := Transform3D(Basis(Vector3.BACK,-PI/3),Vector3(0.29,0.165,0.035))
	shaped_lathe([Vector2(0,0),Vector2(0.17,0),Vector2(0.18,0.012),Vector2(0.145,0.03),Vector2(0,0.04)],"copper",pose)
	sphere(pose*Vector3(0,0.060,0),0.025,"wood")
	collision.append(AABB(Vector3(-0.25,0,-0.175),Vector3(0.35,0.21,0.35)))
	collision.append(pose*AABB(Vector3(-0.18,0,-0.18),Vector3(0.36,0.085,0.36)))

func frying_pan() -> void:
	lathe([Vector2(0,0),Vector2(0.125,0),Vector2(0.16,0.035),Vector2(0.17,0.06),Vector2(0.158,0.065),Vector2(0.145,0.04),Vector2(0.12,0.018),Vector2(0,0.018)],"iron")
	rod(Vector3(0.155,0.045,0),Vector3(0.29,0.065,0),0.015,"steel")
	rod(Vector3(0.27,0.065,0),Vector3(0.47,0.075,0),0.023,"wood")
	hoop(Vector3(0.49,0.075,0),0.010,0.023,"iron",Basis(Vector3.FORWARD,PI*0.5))

func cutting_board() -> void:
	box(Vector3(0,0.016,0),Vector3(0.36,0.032,0.25),"edge")
	box(Vector3(0.205,0.016,0),Vector3(0.10,0.032,0.085),"edge")
	cylinder(Vector3(0.23,0.034,0),0.015,0.003,"wood")
	polygon(PackedVector3Array([Vector3(-0.145,0.039,-0.035),Vector3(0.08,0.039,-0.035),Vector3(0.08,0.039,0.012),Vector3(-0.10,0.039,0.012)]),"steel")
	box(Vector3(0.145,0.047,-0.012),Vector3(0.13,0.025,0.039),"wood")
	for x in [0.105,0.15,0.19]: cylinder(Vector3(x,0.061,-0.012),0.004,0.003,"brass")

func utensil_rail() -> void:
	for x in [-0.32,0.32]:
		box(Vector3(x,0.41,0),Vector3(0.045,0.07,0.13),"iron",true)
		wall_points.append(Vector3(x,0.41,0.065))
	cylinder(Vector3(0,0.41,-0.07),0.015,0.76,"steel",Vector3.RIGHT)
	for x in [-0.23,0,0.23]:
		hoop(Vector3(x,0.385,-0.07),0.017,0.024,"brass",Basis(Vector3.RIGHT,PI*0.5))
		rod(Vector3(x,0.24,-0.08),Vector3(x,0.37,-0.08),0.012,"wood")
	shaped_lathe([Vector2(0,0),Vector2(0.02,0),Vector2(0.054,0.035),Vector2(0.058,0.060),Vector2(0.048,0.060),Vector2(0.042,0.035),Vector2(0.015,0.014),Vector2(0,0.014)],"steel",Transform3D(Basis(Vector3.RIGHT,-PI*0.5),Vector3(-0.23,0.13,-0.08)))
	rod(Vector3(-0.23,0.15,-0.08),Vector3(-0.23,0.26,-0.08),0.007,"steel")
	for x in [-0.030,-0.010,0.010,0.030]: box(Vector3(x,0.18,-0.085),Vector3(0.012,0.11,0.009),"steel")
	box(Vector3(0,0.235,-0.085),Vector3(0.075,0.014,0.009),"steel")
	for plane in 3:
		var points := PackedVector3Array(); var rotation := plane*PI/3
		for index in 33:
			var angle := index*TAU/32.0
			points.append(Vector3(0.23+sin(angle)*0.045*cos(rotation),0.14+cos(angle)*0.085,-0.08+sin(angle)*0.045*sin(rotation)))
		tube(points,0.0035,"steel",6)
	collision.append(AABB(Vector3(-0.30,0.045,-0.15),Vector3(0.60,0.35,0.10)))

func plate_rack() -> void:
	for x in [-0.31,0.31]: box(Vector3(x,0.31,-0.14),Vector3(0.04,0.57,0.31),"wood",true)
	box(Vector3(0,0.10,-0.15),Vector3(0.64,0.045,0.31),"edge",true)
	box(Vector3(0,0.59,0),Vector3(0.66,0.04,0.04),"edge",true)
	box(Vector3(0,0.22,-0.30),Vector3(0.66,0.035,0.035),"edge",true)
	for index in 5:
		var pose := Transform3D(Basis(Vector3.FORWARD,PI*0.5),Vector3(-0.22+index*0.11,0.29,-0.15))
		shaped_lathe([Vector2(0,0),Vector2(0.09,0),Vector2(0.135,0.025),Vector2(0.14,0.034),Vector2(0.13,0.040),Vector2(0.085,0.017),Vector2(0,0.017)],"ceramic",pose)
		var ring := TorusMesh.new(); ring.inner_radius=0.126; ring.outer_radius=0.134; ring.rings=32; ring.ring_segments=6
		append(ring,Transform3D(pose.basis,pose*Vector3(0,0.035,0)),"teal")
	for x in [-0.26,0.26]:
		for y in [0.16,0.54]: wall_points.append(Vector3(x,y,0.02))

func preserve_jars() -> void:
	var centers := [Vector3(-0.14,0,-0.06),Vector3(0.13,0,-0.06),Vector3(0,0,0.15)]
	for index in 3:
		var center: Vector3=centers[index]; var height: float=[0.18,0.24,0.21][index]
		lathe([Vector2(0,0),Vector2(0.05,0),Vector2(0.061,0.015),Vector2(0.061,height-0.035),Vector2(0.048,height-0.015),Vector2(0.048,height),Vector2(0.043,height),Vector2(0.043,height-0.02),Vector2(0.055,height-0.04),Vector2(0.055,0.020),Vector2(0,0.020)],"glass",center)
		cylinder(center+Vector3(0,height+0.006,0),0.054,0.018,"brass" if index!=1 else "ceramic")
		if index==0: cylinder(center+Vector3(0,(height-0.03)*0.5,0),0.048,height-0.05,"beet")
		elif index==1:
			for x in [-0.022,0.022]:
				for z in [-0.020,0.020]: cylinder(center+Vector3(x,0.11,z),0.013,0.15,"pickle")
		else:
			for offset in [Vector3(-0.02,0.06,0),Vector3(0.02,0.095,0.01),Vector3(-0.01,0.13,-0.01),Vector3(0.02,0.15,0)]: sphere(center+offset,0.023,"preserve")
		box(center+Vector3(0,height*0.52,-0.062),Vector3(0.065,0.043,0.002),"linen")
		box(center+Vector3(0,height*0.52,-0.064),Vector3(0.038,0.005,0.001),"rust")

func bread_bin() -> void:
	box(Vector3(0,0.035,0),Vector3(0.44,0.07,0.31),"wood")
	for index in 24:
		var a := index*PI/24.0; var b := (index+1)*PI/24.0
		polygon(PackedVector3Array([Vector3(-0.21,0.08+sin(a)*0.14,cos(a)*0.14),Vector3(0.21,0.08+sin(a)*0.14,cos(a)*0.14),Vector3(0.21,0.08+sin(b)*0.14,cos(b)*0.14),Vector3(-0.21,0.08+sin(b)*0.14,cos(b)*0.14)]),"teal")
	for x in [-0.215,0.215]:
		var points := PackedVector3Array([Vector3(x,0.075,0)])
		for index in 25:
			var angle := index*PI/24.0
			points.append(Vector3(x,0.08+sin(angle)*0.14,cos(angle)*0.14))
		polygon(points,"edge")
	rod(Vector3(-0.075,0.085,-0.155),Vector3(0.075,0.085,-0.155),0.010,"brass")
	for x in [-0.14,0.14]: cylinder(Vector3(x,0.08,0.145),0.012,0.05,"brass",Vector3.RIGHT)
	box(Vector3(0,0.035,-0.158),Vector3(0.10,0.020,0.003),"steel")

func grain_sack() -> void:
	var profile := [Vector2(0.11,0),Vector2(0.18,0.025),Vector2(0.23,0.16),Vector2(0.22,0.34),Vector2(0.17,0.46),Vector2(0.145,0.51),Vector2(0.15,0.54),Vector2(0.132,0.53),Vector2(0.125,0.46)]
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in 40:
		var a := segment*TAU/40.0; var b := (segment+1)*TAU/40.0
		for index in profile.size()-1:
			var p: Vector2=profile[index]; var q: Vector2=profile[index+1]
			var points := [sack_point(p,a),sack_point(p,b),sack_point(q,b),sack_point(q,a)]
			for corner in [0,2,1,0,3,2]: surface.set_uv(Vector2(points[corner].x*4,points[corner].y*4)); surface.add_vertex(points[corner])
	surface.generate_normals(); surface.index(); append(surface.commit(),Transform3D.IDENTITY,"sacking")
	var base := CylinderMesh.new(); base.top_radius=0.113; base.bottom_radius=0.113; base.height=0.014; base.radial_segments=32; base.rings=1
	append(base,Transform3D(Basis.from_scale(Vector3(1.1,1,0.85)),Vector3(0,0.006,0)),"sacking")
	cylinder(Vector3(0,0.475,0),0.125,0.022,"grain")
	var random := RandomNumberGenerator.new(); random.seed=170305
	for index in 42:
		var angle := random.randf()*TAU; var radius := sqrt(random.randf())*0.115
		var kernel := SphereMesh.new(); kernel.radius=0.5; kernel.height=1; kernel.radial_segments=8; kernel.rings=4
		append(kernel,Transform3D(Basis(Vector3.UP,angle)*Basis.from_scale(Vector3(0.016,0.008,0.009)),Vector3(cos(angle)*radius,0.492+0.012*(1-radius/0.115),sin(angle)*radius*0.85)),"grain")
	box(Vector3(0,0.27,-0.191),Vector3(0.14,0.10,0.004),"linen")
	for y in [0.245,0.273,0.30]: box(Vector3(0,y,-0.195),Vector3(0.085,0.005,0.002),"wood")
	var rim := PackedVector3Array()
	for index in 41:
		var angle := index*TAU/40.0
		rim.append(Vector3(cos(angle)*0.154,0.515,sin(angle)*0.127))
	tube(rim,0.004,"linen",6)

func sack_point(profile: Vector2, angle: float) -> Vector3:
	var radius := profile.x*(1+0.035*sin(angle*5+profile.y*9))
	return Vector3(cos(angle)*radius*1.1,profile.y+0.003*cos(angle*3),sin(angle)*radius*0.85)
