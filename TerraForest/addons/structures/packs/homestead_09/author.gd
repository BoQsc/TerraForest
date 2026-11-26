# SPDX-License-Identifier: 0BSD
extends "res://addons/structures/packs/homestead_04/author.gd"
## Original bedroom props using project mesh/tube helpers and Homestead 07 cushions.

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
	for material: Material in materials.values(): material.resource_name=material.resource_name.replace("Homestead 04","Homestead 09")
	materials.wood.albedo_color=Color("6c4c36"); materials.edge.albedo_color=Color("ae8b5d"); materials.fabric.albedo_color=Color("6b8190"); materials.linen.albedo_color=Color("e2d7b9")
	var palette := {"leather":"7e6049","cream":"e3d9bf","blue":"698293","velvet":"3e586b","rubber_red":"a16b5c","ink":"384143","silver":"a7c1c5","glint":"d8e6dd","gem":"6ca6a5"}
	for label: String in palette:
		var material := StandardMaterial3D.new(); material.resource_name="Homestead 09 / "+label; material.albedo_color=Color(palette[label]); material.roughness=0.85; material.cull_mode=BaseMaterial3D.CULL_DISABLED
		if label in ["leather","velvet"]: material.albedo_texture=texture(label=="velvet")
		if label=="silver": material.metallic=0.65; material.roughness=0.18
		if label=="gem": material.metallic=0.3; material.roughness=0.22
		materials[label]=material

func build(slug: String) -> ArrayMesh:
	surfaces.clear(); collision.clear(); wall_points.clear()
	match slug:
		"chest_of_drawers": chest_of_drawers()
		"dressing_table": dressing_table()
		"vanity_stool": vanity_stool()
		"tabletop_mirror": tabletop_mirror()
		"folding_screen": folding_screen()
		"open_suitcase": open_suitcase()
		"blankets": blankets()
		"alarm_clock": alarm_clock()
		"hot_water_bottle": hot_water_bottle()
		"jewellery_box": jewellery_box()
	var raw := ArrayMesh.new()
	for surface: SurfaceTool in surfaces.values(): surface.index(); surface.commit(raw)
	if slug in ["tabletop_mirror","open_suitcase","blankets","alarm_clock","hot_water_bottle","jewellery_box"]: collision.assign([raw.get_aabb()])
	var pose := Transform3D(Basis.IDENTITY,Vector3(0,-raw.get_aabb().position.y,0))
	var mesh := ArrayMesh.new()
	for index in raw.get_surface_count():
		var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); surface.set_material(raw.surface_get_material(index)); surface.append_from(raw,index,pose); surface.commit(mesh)
	for index in collision.size(): collision[index]=pose*collision[index]
	mesh.resource_name="Homestead 09 / "+slug
	mesh.set_meta("pack_id","terraforest.homestead_09"); mesh.set_meta("collision_boxes",collision.duplicate()); mesh.set_meta("authored_size",mesh.get_aabb().size)
	return mesh

func chest_of_drawers() -> void:
	for x in [-0.37,0.37]:
		for z in [-0.15,0.15]: box(Vector3(x,0.065,z),Vector3(0.075,0.13,0.075),"wood",true)
	box(Vector3(0,0.53,0),Vector3(0.88,0.86,0.40),"wood",true)
	box(Vector3(0,0.985,0),Vector3(0.96,0.06,0.45),"edge",true)
	box(Vector3(0,0.135,0),Vector3(0.94,0.055,0.43),"wood",true)
	for index in 4:
		var y := 0.25+index*0.198
		box(Vector3(0,y,-0.213),Vector3(0.79,0.18,0.026),"edge")
		box(Vector3(0,y,-0.230),Vector3(0.73,0.14,0.008),"wood")
		for x in [-0.23,0.23]:
			for offset in [-0.036,0.036]: cylinder(Vector3(x+offset,y,-0.242),0.009,0.008,"brass",Vector3.FORWARD)
			rod(Vector3(x-0.035,y-0.01,-0.25),Vector3(x+0.035,y-0.01,-0.25),0.006,"brass")

func dressing_table() -> void:
	box(Vector3(0,0.765,0),Vector3(1.12,0.055,0.45),"edge",true)
	box(Vector3(-0.37,0.42,0),Vector3(0.28,0.62,0.36),"wood",true)
	for x in [-0.46,-0.28,0.46]:
		for z in [-0.15,0.15]: box(Vector3(x,0.07 if x<0 else 0.365,z),Vector3(0.045,0.14 if x<0 else 0.73,0.045),"wood",true)
	box(Vector3(0.12,0.68,0.17),Vector3(0.72,0.12,0.035),"wood",true)
	box(Vector3(0.12,0.685,-0.19),Vector3(0.69,0.10,0.025),"wood",true)
	for index in 3:
		var y := 0.225+index*0.19
		box(Vector3(-0.37,y,-0.19),Vector3(0.245,0.17,0.025),"wood")
		rod(Vector3(-0.405,y,-0.215),Vector3(-0.335,y,-0.215),0.006,"brass")
	rod(Vector3(0.085,0.685,-0.215),Vector3(0.155,0.685,-0.215),0.006,"brass")
	box(Vector3(0,0.81,0.205),Vector3(1.03,0.065,0.025),"wood",true)

func vanity_stool() -> void:
	for x in [-0.145,0.145]:
		for z in [-0.125,0.125]:
			lathe([Vector2(0,0),Vector2(0.022,0),Vector2(0.025,0.08),Vector2(0.015,0.19),Vector2(0.028,0.29),Vector2(0.027,0.355),Vector2(0,0.355)],"wood",Vector3(x,0,z),20)
			collision.append(AABB(Vector3(x-0.028,0,z-0.028),Vector3(0.056,0.355,0.056)))
	box(Vector3(0,0.345,0),Vector3(0.37,0.04,0.33),"wood",true)
	padded(Vector3(0,0.399,0),Vector3(0.42,0.095,0.38),"fabric")
	for x in [-0.10,0.10]:
		for z in [-0.08,0.08]: sphere(Vector3(x,0.446,z),0.008,"blue")
	collision.append(AABB(Vector3(-0.21,0.35,-0.19),Vector3(0.42,0.095,0.38)))

func tabletop_mirror() -> void:
	box(Vector3(0,0.022,0),Vector3(0.34,0.045,0.18),"edge")
	for x in [-0.17,0.17]:
		rod(Vector3(x,0.04,0),Vector3(x,0.31,0),0.012,"wood")
		cylinder(Vector3(x,0.31,0),0.017,0.038,"brass",Vector3.RIGHT)
	var face := Transform3D(Basis(Vector3.RIGHT,-0.12),Vector3(0,0.31,0))
	var flat := face.basis*Basis.from_scale(Vector3(0.76,1.10,1))*Basis(Vector3.RIGHT,PI*0.5)
	var disc := CylinderMesh.new(); disc.top_radius=0.19; disc.bottom_radius=0.19; disc.height=0.009; disc.radial_segments=48; disc.rings=1
	append(disc,Transform3D(flat,face.origin),"silver")
	var frame := TorusMesh.new(); frame.inner_radius=0.19; frame.outer_radius=0.207; frame.rings=48; frame.ring_segments=8
	append(frame,Transform3D(flat,face.origin),"brass")
	for x in [-0.036,-0.014]: box(face*Vector3(x,0.015,-0.006),Vector3(0.007,0.23,0.001),"glint",false,face.basis*Basis(Vector3.BACK,-0.38))

func screen_box(pose: Transform3D, center: Vector3, size: Vector3, material: String, solid: bool=false) -> void:
	box(pose*center,size,material,solid,pose.basis)

func folding_screen() -> void:
	for panel in 3:
		var angle: float=PI/6 if panel==0 else -PI/6 if panel==2 else 0.0
		var x: float=-0.24-cos(PI/6)*0.24 if panel==0 else 0.24+cos(PI/6)*0.24 if panel==2 else 0.0
		var pose := Transform3D(Basis(Vector3.UP,angle),Vector3(x,0,0.12 if panel!=1 else 0))
		for edge in [-0.23,0.23]: screen_box(pose,Vector3(edge,0.87,0),Vector3(0.035,1.74,0.045),"wood",true)
		for y in [0.17,1.685]: screen_box(pose,Vector3(0,y,0),Vector3(0.46,0.045,0.045),"edge",true)
		screen_box(pose,Vector3(0,0.93,0),Vector3(0.423,1.46,0.014),"fabric",true)
		for y in [0.38,1.47]: screen_box(pose,Vector3(0,y,-0.009),Vector3(0.41,0.012,0.003),"linen")
		for xline in [-0.18,0.18]: screen_box(pose,Vector3(xline,0.93,-0.009),Vector3(0.009,1.42,0.003),"linen")
		for index in 6:
			var y := 0.53+index*0.15
			var diamond := PackedVector3Array([pose*Vector3(0,y+0.025,-0.010),pose*Vector3(0.018,y,-0.010),pose*Vector3(0,y-0.025,-0.010),pose*Vector3(-0.018,y,-0.010)])
			polygon(diamond,"linen")
	for x in [-0.24,0.24]:
		for y in [0.43,1.33]: cylinder(Vector3(x,y,0),0.009,0.09,"brass")

func open_suitcase() -> void:
	box(Vector3(0,0.018,0),Vector3(0.62,0.035,0.42),"leather")
	for x in [-0.299,0.299]: box(Vector3(x,0.09,0),Vector3(0.022,0.15,0.42),"leather")
	for z in [-0.199,0.199]: box(Vector3(0,0.09,z),Vector3(0.60,0.15,0.022),"leather")
	box(Vector3(0,0.041,0),Vector3(0.57,0.012,0.37),"linen")
	padded(Vector3(-0.12,0.091,-0.015),Vector3(0.27,0.075,0.31),"fabric")
	padded(Vector3(0.14,0.09,0),Vector3(0.24,0.075,0.31),"linen")
	padded(Vector3(-0.12,0.14,-0.02),Vector3(0.22,0.035,0.26),"blue")
	for x in [-0.24,-0.01]: padded(Vector3(x,0.13,0.045),Vector3(0.09,0.04,0.12),"blue",Basis(Vector3.UP,0.22 if x<-.1 else -.22))
	for x in [-0.18,0.18]: box(Vector3(x,0.168,0),Vector3(0.027,0.006,0.39),"wood")
	var hinge := Transform3D(Basis(Vector3.RIGHT,deg_to_rad(102)),Vector3(0,0.165,0.20))
	box(hinge*Vector3(0,0,-0.20),Vector3(0.62,0.025,0.42),"leather",false,hinge.basis)
	box(hinge*Vector3(0,-0.016,-0.20),Vector3(0.565,0.008,0.36),"linen",false,hinge.basis)
	for x in [-0.18,0.18]: box(hinge*Vector3(x,-0.023,-0.20),Vector3(0.02,0.005,0.35),"wood",false,hinge.basis)
	for x in [-0.20,0.20]:
		cylinder(Vector3(x,0.165,0.20),0.012,0.06,"brass",Vector3.RIGHT)
		box(Vector3(x,0.12,-0.215),Vector3(0.035,0.06,0.012),"brass")
	tube(PackedVector3Array([Vector3(-0.07,0.09,-0.22),Vector3(-0.07,0.09,-0.27),Vector3(0.07,0.09,-0.27),Vector3(0.07,0.09,-0.22)]),0.01,"wood")

func blankets() -> void:
	var colors := ["linen","fabric","linen"]
	for layer in 3:
		var y := 0.037+layer*0.066
		padded(Vector3(0,y,0),Vector3(0.56-layer*0.012,0.070,0.36),colors[layer])
		for stripe in 4: box(Vector3(-0.21+stripe*0.14,y+0.035,-0.01),Vector3(0.011,0.0015,0.30),"blue" if layer!=1 else "linen")
		rod(Vector3(-0.24,y-0.004,-0.179),Vector3(0.24,y-0.004,-0.179),0.002,"rope")
		for index in 18: rod(Vector3(-0.23+index*0.027,y-0.007,-0.179),Vector3(-0.227+index*0.027,y-0.018,-0.196),0.0014,"linen")

func alarm_clock() -> void:
	cylinder(Vector3(0,0.137,0),0.10,0.06,"blue",Vector3.FORWARD)
	cylinder(Vector3(0,0.137,-0.033),0.092,0.008,"cream",Vector3.FORWARD)
	hoop(Vector3(0,0.137,-0.037),0.090,0.098,"brass",Basis(Vector3.RIGHT,PI*0.5))
	for index in 12:
		var angle := index*TAU/12
		box(Vector3(sin(angle)*0.076,0.137+cos(angle)*0.076,-0.039),Vector3(0.003,0.013,0.001),"ink",false,Basis(Vector3.BACK,-angle))
	rod(Vector3(0,0.137,-0.041),Vector3(-0.035,0.174,-0.041),0.003,"ink")
	rod(Vector3(0,0.137,-0.043),Vector3(0.045,0.165,-0.043),0.002,"ink")
	cylinder(Vector3(0,0.137,-0.046),0.006,0.003,"brass",Vector3.FORWARD)
	for x in [-0.067,0.067]:
		rod(Vector3(x*0.7,0.217,0),Vector3(x,0.297,0),0.008,"brass")
		lathe([Vector2(0.051,0.251),Vector2(0.05,0.262),Vector2(0.043,0.284),Vector2(0.025,0.300),Vector2(0,0.304)],"brass",Vector3(x,0,0))
		rod(Vector3(x*0.80,0.065,0),Vector3(x,0.009,-0.01),0.011,"brass")
	rod(Vector3(0,0.23,0),Vector3(0,0.277,0),0.003,"iron")
	rod(Vector3(-0.019,0.277,0),Vector3(0.019,0.277,0),0.004,"iron")
	for x in [-0.023,0.023]: cylinder(Vector3(x,0.15,0.04),0.012,0.014,"brass",Vector3.BACK)

func hot_water_bottle() -> void:
	padded(Vector3(0,0.133,0),Vector3(0.18,0.25,0.055),"rubber_red")
	cylinder(Vector3(0,0.268,0),0.027,0.052,"rubber_red")
	cylinder(Vector3(0,0.302,0),0.030,0.020,"cream")
	for y in [0.295,0.302,0.309]: hoop(Vector3(0,y,0),0.029,0.031,"cream")
	for index in 13: rod(Vector3(-0.067+index*0.011,0.05,-0.028),Vector3(-0.067+index*0.011,0.21,-0.028),0.0014,"rubber_red")
	tube(PackedVector3Array([Vector3(-0.07,0.035,0),Vector3(-0.087,0.06,0),Vector3(-0.087,0.20,0),Vector3(-0.06,0.25,0),Vector3(-0.027,0.25,0)]),0.002,"leather",6)
	tube(PackedVector3Array([Vector3(0.07,0.035,0),Vector3(0.087,0.06,0),Vector3(0.087,0.20,0),Vector3(0.06,0.25,0),Vector3(0.027,0.25,0)]),0.002,"leather",6)

func jewellery_box() -> void:
	box(Vector3(0,0.01,0),Vector3(0.28,0.02,0.19),"wood")
	for x in [-0.132,0.132]: box(Vector3(x,0.04,0),Vector3(0.016,0.06,0.19),"edge")
	for z in [-0.087,0.087]: box(Vector3(0,0.04,z),Vector3(0.25,0.06,0.016),"edge")
	box(Vector3(0,0.027,0),Vector3(0.245,0.014,0.15),"velvet")
	box(Vector3(-0.025,0.043,0),Vector3(0.01,0.025,0.15),"wood")
	for index in 3:
		var x := 0.015+index*0.034
		hoop(Vector3(x,0.042,-0.025),0.011,0.014,"brass")
		sphere(Vector3(x,0.056,-0.025),0.005,"gem")
	var chain := PackedVector3Array()
	for index in 33:
		var angle := index*TAU/32
		chain.append(Vector3(-0.078+cos(angle)*0.032,0.038,sin(angle)*0.052))
	tube(chain,0.0015,"brass",6)
	var pendant := SphereMesh.new(); pendant.radius=0.009; pendant.height=0.008; pendant.radial_segments=8; pendant.rings=4
	append(pendant,Transform3D(Basis.IDENTITY,Vector3(-0.078,0.042,-0.045)),"gem")
	var hinge := Transform3D(Basis(Vector3.RIGHT,deg_to_rad(100)),Vector3(0,0.07,0.09))
	box(hinge*Vector3(0,0,-0.095),Vector3(0.28,0.016,0.19),"wood",false,hinge.basis)
	box(hinge*Vector3(0,-0.01,-0.095),Vector3(0.24,0.006,0.15),"velvet",false,hinge.basis)
	for x in [-0.09,0.09]: cylinder(Vector3(x,0.07,0.09),0.007,0.035,"brass",Vector3.RIGHT)
	box(Vector3(0,0.05,-0.10),Vector3(0.026,0.03,0.008),"brass")
