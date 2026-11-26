# SPDX-License-Identifier: 0BSD
extends "res://addons/structures/packs/homestead_04/author.gd"
## Original living-room geometry/artwork; inherited offline helpers retain 0BSD.

func _init() -> void:
	super()
	for material: Material in materials.values(): material.resource_name=material.resource_name.replace("Homestead 04","Homestead 07")
	materials.wood.albedo_color=Color("604330"); materials.edge.albedo_color=Color("aa8455"); materials.fabric.albedo_color=Color("527971")
	var palette := {"paper":"ddd6bc","ink":"424746","stone":"9d998a","soot":"333631","ivory":"e4d7ac","vinyl":"20282a","ochre":"b08c4e","wine":"81584e"}
	for label: String in palette:
		var material := StandardMaterial3D.new(); material.resource_name="Homestead 07 / "+label; material.albedo_color=Color(palette[label]); material.roughness=0.85; material.cull_mode=BaseMaterial3D.CULL_DISABLED
		if label=="vinyl": material.roughness=0.30
		if label=="stone": material.albedo_texture=texture(false)
		materials[label]=material
	var news := StandardMaterial3D.new(); news.resource_name="Homestead 07 / original newspaper print"; news.albedo_texture=newspaper_art(); news.roughness=0.95; news.cull_mode=BaseMaterial3D.CULL_DISABLED; materials.news=news

func build(slug: String) -> ArrayMesh:
	surfaces.clear(); collision.clear(); wall_points.clear()
	match slug:
		"armchair": armchair()
		"coffee_table": coffee_table()
		"bookcase": bookcase()
		"sideboard": sideboard()
		"record_player": record_player()
		"record_crate": record_crate()
		"chessboard": chessboard()
		"newspapers": newspapers()
		"floor_lamp": floor_lamp()
		"fireplace": fireplace()
	var raw := ArrayMesh.new()
	for surface: SurfaceTool in surfaces.values(): surface.index(); surface.commit(raw)
	if slug in ["record_player","record_crate","chessboard","newspapers"]: collision.assign([raw.get_aabb()])
	var pose := Transform3D(Basis.IDENTITY,Vector3(0,-raw.get_aabb().position.y,0))
	var mesh := ArrayMesh.new()
	for index in raw.get_surface_count():
		var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); surface.set_material(raw.surface_get_material(index)); surface.append_from(raw,index,pose); surface.commit(mesh)
	for index in collision.size(): collision[index]=pose*collision[index]
	mesh.resource_name="Homestead 07 / "+slug
	mesh.set_meta("pack_id","terraforest.homestead_07"); mesh.set_meta("collision_boxes",collision.duplicate()); mesh.set_meta("authored_size",mesh.get_aabb().size)
	return mesh

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

func armchair() -> void:
	for x in [-0.31,0.31]:
		for z in [-0.28,0.28]: box(Vector3(x,0.12,z),Vector3(0.075,0.24,0.075),"wood",true,Basis(Vector3.BACK,x*0.14))
	box(Vector3(0,0.27,0),Vector3(0.76,0.12,0.68),"wood",true)
	padded(Vector3(0,0.39,-0.04),Vector3(0.64,0.19,0.63),"fabric")
	padded(Vector3(0,0.67,0.265),Vector3(0.76,0.70,0.20),"fabric",Basis(Vector3.RIGHT,0.13))
	for x in [-0.385,0.385]:
		padded(Vector3(x,0.49,0),Vector3(0.17,0.42,0.75),"fabric")
		collision.append(AABB(Vector3(x-0.085,0.28,-0.375),Vector3(0.17,0.42,0.75)))
		rod(Vector3(x,0.70,-0.28),Vector3(x,0.70,0.24),0.003,"linen")
	for x in [-0.20,0,0.20]:
		for y in [0.65,0.83]: sphere(Vector3(x,y,0.151),0.011,"teal")
	collision.append(AABB(Vector3(-0.32,0.30,-0.35),Vector3(0.64,0.19,0.63)))
	collision.append(AABB(Vector3(-0.38,0.33,0.13),Vector3(0.76,0.70,0.25)))

func coffee_table() -> void:
	box(Vector3(0,0.405,0),Vector3(1.10,0.055,0.57),"edge",true)
	box(Vector3(0,0.365,0),Vector3(1.04,0.025,0.51),"wood",true)
	for x in [-0.44,0.44]:
		for z in [-0.20,0.20]: box(Vector3(x,0.18,z),Vector3(0.06,0.36,0.06),"wood",true)
	for index in 7: box(Vector3(-0.39+index*0.13,0.12,0),Vector3(0.10,0.035,0.42),"wood",true)
	for z in [-0.18,0.18]: box(Vector3(0,0.095,z),Vector3(0.94,0.04,0.045),"wood",true)

func bookcase() -> void:
	for x in [-0.485,0.485]: box(Vector3(x,0.94,0),Vector3(0.065,1.82,0.32),"wood",true)
	box(Vector3(0,0.93,0.145),Vector3(0.95,1.80,0.025),"wood",true)
	for level in 6: box(Vector3(0,0.055+level*0.355,0),Vector3(1.04,0.055,0.35),"edge",true)
	var colours := ["teal","wine","ochre","linen","wood"]
	for shelf in 5:
		var x := -0.405
		for index in 11:
			var width := 0.035+(index%3)*0.010
			var height := 0.22+0.028*((index+shelf)%4)
			box(Vector3(x+width*0.5,0.0825+shelf*0.355+height*0.5,0.025),Vector3(width,height,0.205),colours[(index+shelf)%5])
			for stripe in [0.04,0.16]: box(Vector3(x+width*0.5,0.0825+shelf*0.355+stripe,-0.079),Vector3(width*0.68,0.004,0.002),"brass")
			x+=width+0.008
		# Open space and a horizontal pair keep the shelves visibly distinct.
		for index in 2: box(Vector3(0.335,0.095+shelf*0.355+index*0.027,0.015),Vector3(0.20,0.025,0.22),colours[(shelf+index)%5])

func sideboard() -> void:
	for x in [-0.63,0.63]:
		for z in [-0.18,0.18]: box(Vector3(x,0.095,z),Vector3(0.065,0.19,0.065),"wood",true)
	box(Vector3(0,0.46,0),Vector3(1.48,0.62,0.43),"wood",true)
	box(Vector3(0,0.80,0),Vector3(1.56,0.065,0.48),"edge",true)
	for index in 3:
		var x := -0.48+index*0.48
		box(Vector3(x,0.44,-0.23),Vector3(0.455,0.45,0.025),"edge")
		box(Vector3(x,0.44,-0.246),Vector3(0.40,0.39,0.008),"wood")
		rod(Vector3(x+0.145,0.42,-0.265),Vector3(x+0.145,0.52,-0.265),0.007,"brass")
		box(Vector3(x,0.715,-0.23),Vector3(0.455,0.095,0.025),"wood")
		rod(Vector3(x-0.045,0.715,-0.25),Vector3(x+0.045,0.715,-0.25),0.007,"brass")

func record_player() -> void:
	box(Vector3(0,0.06,0),Vector3(0.42,0.10,0.34),"wood")
	box(Vector3(0,0.117,0),Vector3(0.39,0.014,0.315),"linen")
	for x in [-0.155,0.155]:
		for z in [-0.12,0.12]: cylinder(Vector3(x,0.009,z),0.018,0.018,"rubber")
	cylinder(Vector3(-0.045,0.131,-0.018),0.132,0.018,"steel")
	cylinder(Vector3(-0.045,0.142,-0.018),0.126,0.004,"vinyl")
	for index in 10: hoop(Vector3(-0.045,0.145,-0.018),0.058+index*0.006,0.059+index*0.006,"iron")
	cylinder(Vector3(-0.045,0.146,-0.018),0.037,0.002,"wine")
	cylinder(Vector3(-0.045,0.151,-0.018),0.003,0.014,"steel")
	cylinder(Vector3(0.143,0.151,0.091),0.017,0.050,"brass")
	tube(PackedVector3Array([Vector3(0.143,0.18,0.091),Vector3(0.155,0.18,0.045),Vector3(0.10,0.172,-0.03),Vector3(0.08,0.165,-0.095)]),0.005,"steel")
	box(Vector3(0.08,0.157,-0.10),Vector3(0.026,0.018,0.032),"vinyl")
	cylinder(Vector3(0.151,0.132,-0.13),0.015,0.016,"brass")
	var basis := Basis(Vector3.RIGHT,deg_to_rad(72))
	var hinge := Transform3D(basis,Vector3(0,0.125,0.16))
	box(hinge*Vector3(0,0,-0.16),Vector3(0.42,0.022,0.33),"wood",false,basis)
	box(hinge*Vector3(0,-0.013,-0.16),Vector3(0.37,0.008,0.28),"linen",false,basis)
	for x in [-0.14,0.14]: cylinder(Vector3(x,0.125,0.16),0.011,0.055,"brass",Vector3.RIGHT)

func record_crate() -> void:
	box(Vector3(0,0.025,0),Vector3(0.40,0.035,0.40),"wood")
	for x in [-0.18,0.18]:
		for z in [-0.18,0.18]: box(Vector3(x,0.135,z),Vector3(0.035,0.25,0.035),"wood")
	for y in [0.075,0.17,0.255]:
		for z in [-0.18,0.18]: box(Vector3(0,y,z),Vector3(0.39,0.055,0.022),"edge")
		for x in [-0.18,0.18]: box(Vector3(x,y,0),Vector3(0.022,0.055,0.36),"wood")
	var colours := ["wine","teal","ochre","linen"]
	for index in 7:
		var z := -0.125+index*0.040
		box(Vector3(0,0.195,z),Vector3(0.31,0.31,0.012),colours[index%4])
		cylinder(Vector3(0.015,0.225,z-0.007),0.115,0.004,"vinyl",Vector3.FORWARD)
		cylinder(Vector3(0.015,0.225,z-0.010),0.031,0.002,colours[(index+2)%4],Vector3.FORWARD)
		box(Vector3(-0.10,0.325,z-0.009),Vector3(0.035,0.035,0.002),"paper")

func chessboard() -> void:
	box(Vector3(0,0.016,0),Vector3(0.46,0.032,0.46),"wood")
	for row in 8:
		for column in 8:
			box(Vector3(-0.175+column*0.050,0.034,-0.175+row*0.050),Vector3(0.050,0.005,0.050),"ivory" if (row+column)%2==0 else "wood")
	var order := ["rook","knight","bishop","queen","king","bishop","knight","rook"]
	for side in 2:
		var material := "ivory" if side==0 else "vinyl"
		for column in 8:
			chess_piece("pawn",Vector3(-0.175+column*0.050,0.037,-0.125 if side==0 else 0.125),material,side)
			chess_piece(order[column],Vector3(-0.175+column*0.050,0.037,-0.175 if side==0 else 0.175),material,side)

func chess_piece(kind: String, origin: Vector3, material: String, side: int) -> void:
	var height := 0.035 if kind=="pawn" else 0.055
	if kind in ["king","queen"]: height=0.065
	lathe([Vector2(0,0),Vector2(0.017,0),Vector2(0.017,0.006),Vector2(0.012,0.011),Vector2(0.006,height*0.70),Vector2(0.011,height),Vector2(0,height)],material,origin,16)
	match kind:
		"pawn": sphere(origin+Vector3(0,height+0.006,0),0.010,material)
		"rook":
			cylinder(origin+Vector3(0,height+0.004,0),0.014,0.009,material)
			for index in 4: box(origin+Vector3(cos(index*PI*0.5)*0.010,height+0.012,sin(index*PI*0.5)*0.010),Vector3(0.008,0.009,0.008),material)
		"knight":
			var basis := Basis(Vector3.UP,side*PI)
			box(origin+basis*Vector3(0,height+0.011,0.002),Vector3(0.015,0.030,0.014),material,false,basis*Basis(Vector3.RIGHT,-0.30))
			padded(origin+basis*Vector3(0,height+0.025,-0.008),Vector3(0.015,0.015,0.027),material,basis)
			for x in [-0.005,0.005]: box(origin+basis*Vector3(x,height+0.039,0.002),Vector3(0.004,0.011,0.006),material)
		"bishop":
			padded(origin+Vector3(0,height+0.012,0),Vector3(0.016,0.027,0.016),material)
			box(origin+Vector3(0,height+0.016,-0.0085),Vector3(0.002,0.016,0.001),"brass",false,Basis(Vector3.BACK,0.45))
		"queen":
			hoop(origin+Vector3(0,height+0.007,0),0.008,0.013,material)
			for index in 6: sphere(origin+Vector3(cos(index*TAU/6)*0.010,height+0.014,sin(index*TAU/6)*0.010),0.0035,material)
		"king":
			box(origin+Vector3(0,height+0.014,0),Vector3(0.006,0.026,0.006),material)
			box(origin+Vector3(0,height+0.018,0),Vector3(0.022,0.006,0.006),material)

func newspapers() -> void:
	for index in 9:
		box(Vector3(sin(index)*0.006,0.002+index*0.0028,0),Vector3(0.40,0.0025,0.29),"paper",false,Basis(Vector3.UP,0.015 if index%2==0 else -0.015))
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [Vector3(-0.198,0.026,-0.142),Vector3(0.198,0.026,-0.142),Vector3(0.198,0.026,0.142),Vector3(-0.198,0.026,0.142)]
	var uvs := [Vector2(1,0),Vector2(0,0),Vector2(0,1),Vector2(1,1)]
	for corner in [0,1,2,0,2,3]: surface.set_normal(Vector3.UP); surface.set_uv(uvs[corner]); surface.add_vertex(points[corner])
	surface.index(); append(surface.commit(),Transform3D.IDENTITY,"news")
	rod(Vector3(0,0.026,-0.14),Vector3(0,0.026,0.14),0.001,"linen")

func newspaper_art() -> ImageTexture:
	var image := Image.create(384,256,false,Image.FORMAT_RGB8); image.fill(Color("dfd7bd"))
	var ink := Color("4b504a")
	image.fill_rect(Rect2i(12,10,360,3),ink); image.fill_rect(Rect2i(12,44,360,2),ink)
	# Original abstract masthead and article marks; no external text or font.
	for index in 19: image.fill_rect(Rect2i(16+index*19,19,12,16+(index%3)*2),ink)
	for column in 3:
		for row in 27:
			var width := 93-(row%4)*5
			image.fill_rect(Rect2i(14+column*123,55+row*7,width,2),ink)
	image.fill_rect(Rect2i(140,57,94,67),Color("939988"))
	image.fill_rect(Rect2i(149,80,30,36),Color("5e7369")); image.fill_rect(Rect2i(182,68,42,48),Color("728578"))
	image.fill_rect(Rect2i(144,118,86,3),ink)
	return ImageTexture.create_from_image(image)

func floor_lamp() -> void:
	lathe([Vector2(0,0.005),Vector2(0.19,0.005),Vector2(0.19,0.025),Vector2(0.16,0.055),Vector2(0.04,0.07),Vector2(0,0.07)],"brass")
	cylinder(Vector3(0,0.75,0),0.016,1.38,"brass")
	sphere(Vector3(0,1.46,0),0.055,"bulb")
	lathe([Vector2(0.275,1.30),Vector2(0.285,1.30),Vector2(0.17,1.70),Vector2(0.158,1.70),Vector2(0.275,1.30)],"linen")
	for value in [Vector3(0.275,1.30,0.285),Vector3(0.158,1.70,0.17)]: hoop(Vector3(0,value.y,0),value.x,value.z,"teal")
	for index in 20:
		var angle := index*TAU/20
		rod(Vector3(cos(angle)*0.282,1.305,sin(angle)*0.282),Vector3(cos(angle)*0.168,1.695,sin(angle)*0.168),0.002,"linen")
	rod(Vector3(0.09,1.45,0),Vector3(0.09,1.12,0),0.0017,"brass"); sphere(Vector3(0.09,1.115,0),0.007,"brass")
	collision.append(AABB(Vector3(-0.19,0,-0.19),Vector3(0.38,0.07,0.38)))
	collision.append(AABB(Vector3(-0.017,0.07,-0.017),Vector3(0.034,1.23,0.034)))
	collision.append(AABB(Vector3(-0.285,1.30,-0.285),Vector3(0.57,0.40,0.57)))

func fireplace() -> void:
	box(Vector3(0,0.055,-0.025),Vector3(1.46,0.11,0.49),"stone",true)
	box(Vector3(0,0.61,0.145),Vector3(1.20,1.0,0.035),"soot",true)
	for x in [-0.49,0.49]:
		for row in 4: box(Vector3(x,0.19+row*0.165,0),Vector3(0.22,0.16,0.30),"stone",true)
	for index in 9:
		var a := index*PI/9+0.012; var b := (index+1)*PI/9-0.012
		var ring := PackedVector3Array([Vector3(cos(a)*0.38,0.765+sin(a)*0.38,0),Vector3(cos(a)*0.60,0.765+sin(a)*0.60,0),Vector3(cos(b)*0.60,0.765+sin(b)*0.60,0),Vector3(cos(b)*0.38,0.765+sin(b)*0.38,0)])
		var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for side in [-1,1]:
			for corner in [0,1,2,0,2,3]: surface.set_uv(Vector2(ring[corner].x,ring[corner].y)); surface.add_vertex(ring[corner]+Vector3(0,0,side*0.15))
		for edge in 4:
			var p := ring[edge]; var q := ring[(edge+1)%4]
			for point in [p+Vector3(0,0,-0.15),q+Vector3(0,0,-0.15),q+Vector3(0,0,0.15),p+Vector3(0,0,-0.15),q+Vector3(0,0,0.15),p+Vector3(0,0,0.15)]: surface.set_uv(Vector2(point.x,point.y)); surface.add_vertex(point)
		surface.generate_normals(); surface.index(); append(surface.commit(),Transform3D.IDENTITY,"stone")
		var low := ring[0].min(ring[1]).min(ring[2]).min(ring[3]); var high := ring[0].max(ring[1]).max(ring[2]).max(ring[3])
		collision.append(AABB(low+Vector3(0,0,-0.15),high-low+Vector3(0,0,0.30)))
	box(Vector3(0,1.405,0),Vector3(1.40,0.08,0.40),"edge",true)
	box(Vector3(0,1.35,0.10),Vector3(1.23,0.045,0.12),"wood",true)
	for z in [-0.095,0.06]:
		cylinder(Vector3(0,0.205,z),0.052,0.58,"wood",Vector3.RIGHT)
		for x in [-0.292,0.292]: cylinder(Vector3(x,0.205,z),0.049,0.003,"edge",Vector3.RIGHT)
	cylinder(Vector3(0,0.29,-0.015),0.048,0.55,"wood",Vector3.RIGHT)
	for x in [-0.24,0.24]: box(Vector3(x,0.16,-0.02),Vector3(0.022,0.10,0.29),"iron")
	for index in 7: rod(Vector3(-0.28+index*0.093,0.16,-0.145),Vector3(-0.28+index*0.093,0.24,-0.15),0.007,"iron")
	rod(Vector3(-0.31,0.21,-0.15),Vector3(0.31,0.21,-0.15),0.009,"iron")
	collision.append(AABB(Vector3(-0.32,0.11,-0.17),Vector3(0.64,0.23,0.30)))
