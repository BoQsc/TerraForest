# SPDX-License-Identifier: 0BSD
extends "res://addons/structures/packs/homestead_04/author.gd"
## Original study props and printed artwork; offline mesh/tube helpers are 0BSD.

func _init() -> void:
	super()
	for material: Material in materials.values(): material.resource_name=material.resource_name.replace("Homestead 04","Homestead 06")
	materials.wood.albedo_color=Color("513c30"); materials.edge.albedo_color=Color("98764f"); materials.fabric.albedo_color=Color("496c69")
	var palette := {"cream":"ded6bb","bakelite":"293539","paper":"e5dfc9","leather":"72523d"}
	for label: String in palette:
		var material := StandardMaterial3D.new(); material.resource_name="Homestead 06 / "+label; material.albedo_color=Color(palette[label]); material.roughness=0.82; material.cull_mode=BaseMaterial3D.CULL_DISABLED
		if label=="bakelite": material.roughness=0.32
		materials[label]=material
	var pixels := Image.create(128,128,false,Image.FORMAT_RGB8)
	var random := RandomNumberGenerator.new(); random.seed=170306
	for y in 128:
		for x in 128:
			var value := 0.83+random.randf()*0.13+0.025*sin(x*0.16+y*0.09)
			pixels.set_pixel(x,y,Color(value,value,value))
	materials.leather.albedo_texture=ImageTexture.create_from_image(pixels)
	var artwork := StandardMaterial3D.new(); artwork.resource_name="Homestead 06 / original calendar print"; artwork.albedo_texture=calendar_art(); artwork.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; artwork.cull_mode=BaseMaterial3D.CULL_DISABLED; materials.calendar_art=artwork

func cushion(center: Vector3, size: Vector3, material: String, basis: Basis=Basis.IDENTITY) -> void:
	var mesh := SphereMesh.new(); mesh.radius=0.5; mesh.height=1; mesh.radial_segments=24; mesh.rings=12
	append(mesh,Transform3D(basis*Basis.from_scale(size),center),material)

func build(slug: String) -> ArrayMesh:
	surfaces.clear(); collision.clear(); wall_points.clear()
	match slug:
		"writing_desk": writing_desk()
		"desk_chair": desk_chair()
		"typewriter": typewriter()
		"radio": radio()
		"telephone": telephone()
		"desk_fan": desk_fan()
		"documents": documents()
		"calendar": wall_calendar()
		"briefcase": briefcase()
		"wastebasket": wastebasket()
	var raw := ArrayMesh.new()
	for surface: SurfaceTool in surfaces.values(): surface.index(); surface.commit(raw)
	if slug in ["typewriter","radio","telephone","documents","briefcase"]: collision.assign([raw.get_aabb()])
	var pose := Transform3D(Basis.IDENTITY,Vector3(0,-raw.get_aabb().position.y,0))
	var mesh := ArrayMesh.new()
	for index in raw.get_surface_count():
		var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); surface.set_material(raw.surface_get_material(index)); surface.append_from(raw,index,pose); surface.commit(mesh)
	for index in collision.size(): collision[index]=pose*collision[index]
	for index in wall_points.size(): wall_points[index]=pose*wall_points[index]
	mesh.resource_name="Homestead 06 / "+slug
	mesh.set_meta("pack_id","terraforest.homestead_06"); mesh.set_meta("collision_boxes",collision.duplicate()); mesh.set_meta("authored_size",mesh.get_aabb().size)
	if not wall_points.is_empty(): mesh.set_meta("wall_support_points",wall_points)
	return mesh

func writing_desk() -> void:
	box(Vector3(0,0.765,0),Vector3(1.32,0.075,0.64),"edge",true)
	for z in [-0.245,0.245]: box(Vector3(-0.55,0.365,z),Vector3(0.075,0.73,0.075),"wood",true)
	box(Vector3(0.43,0.365,0.015),Vector3(0.36,0.69,0.53),"wood",true)
	box(Vector3(-0.10,0.64,0.24),Vector3(0.92,0.12,0.045),"wood",true)
	for index in 3:
		var y := 0.20+index*0.19
		box(Vector3(0.43,y,-0.268),Vector3(0.32,0.16,0.035),"wood")
		rod(Vector3(0.38,y,-0.295),Vector3(0.48,y,-0.295),0.008,"brass")
	box(Vector3(-0.18,0.665,-0.272),Vector3(0.75,0.10,0.025),"wood")
	rod(Vector3(-0.23,0.665,-0.292),Vector3(-0.13,0.665,-0.292),0.007,"brass")

func desk_chair() -> void:
	cylinder(Vector3(0,0.26,0),0.025,0.34,"steel")
	for index in 5:
		var angle := index*TAU/5
		var end := Vector3(cos(angle)*0.25,0.07,sin(angle)*0.25)
		rod(Vector3(0,0.12,0),end,0.018,"iron")
		cylinder(Vector3(end.x,0.044,end.z),0.044,0.036,"bakelite",Vector3(-sin(angle),0,cos(angle)))
	box(Vector3(0,0.425,0),Vector3(0.45,0.035,0.41),"iron")
	cushion(Vector3(0,0.48,0),Vector3(0.50,0.13,0.46),"fabric")
	rod(Vector3(0,0.43,0.13),Vector3(0,0.74,0.22),0.020,"iron")
	cushion(Vector3(0,0.76,0.21),Vector3(0.47,0.52,0.12),"fabric",Basis(Vector3.RIGHT,deg_to_rad(10)))
	for x in [-0.275,0.275]:
		rod(Vector3(x*0.85,0.44,0.10),Vector3(x,0.63,0.10),0.012,"iron")
		cushion(Vector3(x,0.64,-0.005),Vector3(0.065,0.045,0.31),"bakelite")
		collision.append(AABB(Vector3(x-0.04,0.61,-0.16),Vector3(0.08,0.065,0.32)))
	collision.append(AABB(Vector3(-0.30,0,-0.30),Vector3(0.60,0.14,0.60)))
	collision.append(AABB(Vector3(-0.25,0.42,-0.23),Vector3(0.50,0.13,0.46)))
	collision.append(AABB(Vector3(-0.24,0.51,0.105),Vector3(0.48,0.52,0.20)))

func typewriter() -> void:
	box(Vector3(0,0.045,0),Vector3(0.38,0.07,0.32),"cream")
	box(Vector3(0,0.095,-0.065),Vector3(0.35,0.045,0.19),"bakelite",false,Basis(Vector3.RIGHT,-0.20))
	for row in 4:
		for column in 10-row/2:
			var x := -0.14+column*0.031+row*0.006
			var y := 0.105+row*0.014; var z := -0.13+row*0.042
			cylinder(Vector3(x,y-0.007,z),0.004,0.016,"steel")
			cylinder(Vector3(x,y+0.005,z),0.010,0.007,"cream")
			box(Vector3(x,y+0.010,z),Vector3(0.004,0.001,0.002),"bakelite")
	box(Vector3(0,0.073,-0.19),Vector3(0.16,0.014,0.025),"bakelite")
	cylinder(Vector3(0,0.205,0.09),0.024,0.41,"bakelite",Vector3.RIGHT)
	for x in [-0.225,0.225]: cylinder(Vector3(x,0.205,0.09),0.028,0.025,"bakelite",Vector3.RIGHT)
	for x in [-0.165,0.165]: rod(Vector3(x,0.12,0.08),Vector3(x,0.25,0.08),0.009,"steel")
	rod(Vector3(-0.18,0.25,0.08),Vector3(0.18,0.25,0.08),0.006,"steel")
	box(Vector3(0,0.345,0.106),Vector3(0.235,0.235,0.002),"paper")
	for line in 7: box(Vector3(-0.015,0.29+line*0.020,0.103),Vector3(0.17-line*0.006,0.002,0.001),"iron")
	rod(Vector3(-0.18,0.23,0.11),Vector3(-0.29,0.26,0.13),0.008,"steel")
	cylinder(Vector3(-0.30,0.26,0.13),0.012,0.045,"bakelite",Vector3.RIGHT)

func radio() -> void:
	box(Vector3(0,0.13,0),Vector3(0.36,0.23,0.17),"wood")
	box(Vector3(0,0.13,-0.091),Vector3(0.33,0.20,0.015),"cream")
	box(Vector3(-0.065,0.14,-0.102),Vector3(0.17,0.14,0.005),"linen")
	for index in 19: cylinder(Vector3(-0.145+index*0.009,0.14,-0.108),0.0017,0.14,"iron")
	for index in 6: rod(Vector3(-0.15,0.075+index*0.026,-0.110),Vector3(0.02,0.075+index*0.026,-0.110),0.0014,"iron")
	for y in [0.075,0.14]:
		cylinder(Vector3(0.105,y,-0.11),0.022,0.020,"bakelite",Vector3.FORWARD)
		box(Vector3(0.105,y+0.011,-0.123),Vector3(0.003,0.012,0.002),"steel")
	box(Vector3(0.10,0.195,-0.103),Vector3(0.075,0.027,0.003),"linen")
	for index in 8: box(Vector3(0.070+index*0.008,0.196,-0.106),Vector3(0.001,0.018 if index%2==0 else 0.010,0.001),"iron")
	for x in [-0.07,0.07]: rod(Vector3(x,0.245,0),Vector3(x,0.295,0),0.009,"bakelite")
	rod(Vector3(-0.07,0.295,0),Vector3(0.07,0.295,0),0.012,"bakelite")
	rod(Vector3(0.145,0.245,0.045),Vector3(0.17,0.405,0.045),0.003,"steel")
	sphere(Vector3(0.17,0.405,0.045),0.006,"steel")

func telephone() -> void:
	box(Vector3(0,0.055,0),Vector3(0.25,0.09,0.23),"bakelite")
	var dial := Transform3D(Basis(Vector3.RIGHT,-0.25),Vector3(0,0.113,-0.035))
	var disc := CylinderMesh.new(); disc.top_radius=0.077; disc.bottom_radius=0.077; disc.height=0.010; disc.radial_segments=40; disc.rings=1
	append(disc,dial,"steel")
	for index in 10:
		var angle := index*TAU/11+0.45
		var hole := CylinderMesh.new(); hole.top_radius=0.009; hole.bottom_radius=0.009; hole.height=0.002; hole.radial_segments=12; hole.rings=1
		append(hole,Transform3D(dial.basis,dial*Vector3(cos(angle)*0.055,0.007,sin(angle)*0.055)),"bakelite")
	var center := CylinderMesh.new(); center.top_radius=0.025; center.bottom_radius=0.025; center.height=0.003; center.radial_segments=24; center.rings=1
	append(center,Transform3D(dial.basis,dial*Vector3(0,0.008,0)),"linen")
	for x in [-0.11,0.11]: box(Vector3(x,0.135,0.067),Vector3(0.025,0.09,0.035),"bakelite")
	tube(PackedVector3Array([Vector3(-0.14,0.17,0.06),Vector3(-0.13,0.235,0.06),Vector3(0,0.27,0.06),Vector3(0.13,0.235,0.06),Vector3(0.14,0.17,0.06)]),0.022,"bakelite")
	for x in [-0.14,0.14]: cushion(Vector3(x,0.17,0.06),Vector3(0.072,0.055,0.075),"bakelite")
	var cord := PackedVector3Array([Vector3(-0.13,0.055,0.06)])
	for index in 161:
		var t := index/160.0; var angle := t*TAU*12
		cord.append(Vector3(-0.18-0.12*sin(t*PI)+0.008*cos(angle),0.045+0.11*t+0.008*sin(angle),0.06-0.15*sin(t*PI)))
	cord.append(Vector3(-0.14,0.17,0.06)); tube(cord,0.0035,"bakelite",6)

func desk_fan() -> void:
	cushion(Vector3(0,0.022,0.015),Vector3(0.20,0.044,0.17),"teal")
	rod(Vector3(0,0.04,0.025),Vector3(0,0.31,0.04),0.019,"steel")
	cylinder(Vector3(0,0.37,0.025),0.055,0.12,"teal",Vector3.FORWARD)
	var center := Vector3(0,0.37,-0.06)
	for index in 3:
		var basis := Basis(Vector3.BACK,index*TAU/3)
		var points := PackedVector3Array()
		for point in [Vector3(0.015,0.015,0),Vector3(0.045,0.13,0),Vector3(0.125,0.075,0),Vector3(0.060,-0.015,0)]: points.append(center+basis*point)
		polygon(points,"teal")
	for radius in [0.055,0.105,0.155]: hoop(center+Vector3(0,0,-0.03),radius-0.0016,radius+0.0016,"steel",Basis(Vector3.RIGHT,PI*0.5))
	hoop(center+Vector3(0,0,0.06),0.150,0.157,"steel",Basis(Vector3.RIGHT,PI*0.5))
	for index in 24:
		var angle := index*TAU/24
		rod(center+Vector3(cos(angle)*0.031,sin(angle)*0.031,-0.03),center+Vector3(cos(angle)*0.155,sin(angle)*0.155,-0.03),0.0018,"steel")
	sphere(center+Vector3(0,0,-0.043),0.032,"cream")
	cylinder(Vector3(0.067,0.37,0.025),0.013,0.025,"bakelite",Vector3.RIGHT)
	collision.append(AABB(Vector3(-0.10,0,-0.07),Vector3(0.20,0.05,0.17)))
	collision.append(AABB(Vector3(-0.025,0.04,0.01),Vector3(0.05,0.28,0.06)))
	collision.append(AABB(Vector3(-0.16,0.21,-0.11),Vector3(0.32,0.32,0.20)))

func documents() -> void:
	box(Vector3(0,0.004,0),Vector3(0.34,0.008,0.26),"teal")
	box(Vector3(0.115,0.005,0.14),Vector3(0.08,0.008,0.025),"teal")
	for index in 11:
		var turn := (-0.025 if index%2==0 else 0.025)
		box(Vector3(sin(index)*0.006,0.010+index*0.0023,0),Vector3(0.30,0.002,0.22),"paper",false,Basis(Vector3.UP,turn))
	for index in 8: box(Vector3(-0.012,0.036,-0.075+index*0.018),Vector3(0.21-index*0.009,0.001,0.002),"iron")
	for x in [-0.105,0.105]: tube(PackedVector3Array([Vector3(x,0.004,-0.12),Vector3(x,0.04,-0.11),Vector3(x,0.04,0.11),Vector3(x,0.004,0.12)]),0.0025,"rope",6)

func wall_calendar() -> void:
	box(Vector3(0,0.25,0),Vector3(0.31,0.45,0.008),"paper",true)
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := [Vector3(-0.15,0.03,-0.005),Vector3(0.15,0.03,-0.005),Vector3(0.15,0.47,-0.005),Vector3(-0.15,0.47,-0.005)]
	var uvs := [Vector2(1,1),Vector2(0,1),Vector2(0,0),Vector2(1,0)]
	for corner in [0,2,1,0,3,2]: surface.set_normal(Vector3.FORWARD); surface.set_uv(uvs[corner]); surface.add_vertex(points[corner])
	surface.index(); append(surface.commit(),Transform3D.IDENTITY,"calendar_art")
	box(Vector3(0,0.49,0),Vector3(0.33,0.035,0.035),"edge",true)
	hoop(Vector3(0,0.525,0),0.013,0.018,"iron",Basis(Vector3.RIGHT,PI*0.5))
	wall_points=PackedVector3Array([Vector3(-0.11,0.49,0.0175),Vector3(0.11,0.49,0.0175)])

func calendar_art() -> ImageTexture:
	var image := Image.create(256,384,false,Image.FORMAT_RGB8); image.fill(Color("e6dfca"))
	image.fill_rect(Rect2i(0,0,256,80),Color("416764"))
	draw_number(image,11,Vector2i(20,17),5,Color("e8dfc7")); draw_number(image,2026,Vector2i(118,26),3,Color("e8dfc7"))
	for column in 7: draw_number(image,column+1,Vector2i(29+column*32,97),1,Color("6d726c"))
	for row in 7: image.fill_rect(Rect2i(16,116+row*40,224,1),Color("b9b29d"))
	for column in 8: image.fill_rect(Rect2i(16+column*32,116,1,241),Color("b9b29d"))
	# Original seven-segment glyph art. November 2026 starts on Sunday (column 6).
	for day in range(1,31):
		var slot := day+5; var row := slot/7; var column := slot%7
		var position := Vector2i(16+column*32,116+row*40)
		if day==26: image.fill_rect(Rect2i(position+Vector2i(2,2),Vector2i(29,37)),Color("a66a50"))
		var color := Color("f0e7d3") if day==26 else Color("975844") if column>=5 else Color("3d4947")
		draw_number(image,day,position+Vector2i(5,11),2,color)
	return ImageTexture.create_from_image(image)

func draw_number(image: Image, number: int, position: Vector2i, scale: int, color: Color) -> void:
	var glyphs := ["abcdef","bc","abdeg","abcdg","bcfg","acdfg","acdefg","abc","abcdefg","abcdfg"]
	var segments := [Rect2i(1,0,3,1),Rect2i(4,1,1,3),Rect2i(4,5,1,3),Rect2i(1,8,3,1),Rect2i(0,5,1,3),Rect2i(0,1,1,3),Rect2i(1,4,3,1)]
	for digit in str(number):
		for letter in glyphs[int(digit)]:
			var segment: Rect2i=segments["abcdefg".find(letter)]
			image.fill_rect(Rect2i(position+segment.position*scale,segment.size*scale),color)
		position.x+=6*scale

func briefcase() -> void:
	box(Vector3(0,0.145,0),Vector3(0.40,0.27,0.12),"leather")
	box(Vector3(0,0.145,-0.063),Vector3(0.37,0.24,0.007),"leather")
	for x in [-0.185,0.185]: box(Vector3(x,0.145,-0.068),Vector3(0.008,0.235,0.003),"wood")
	for y in [0.03,0.26]: box(Vector3(0,y,-0.068),Vector3(0.37,0.007,0.003),"wood")
	for x in [-0.12,0.12]: box(Vector3(x,0.245,-0.073),Vector3(0.025,0.05,0.014),"brass")
	var handle := PackedVector3Array()
	for index in 17:
		var angle := index*PI/16
		handle.append(Vector3(cos(angle)*0.07,0.28+sin(angle)*0.065,0))
	tube(handle,0.009,"bakelite")
	for x in [-0.16,0.16]: box(Vector3(x,0.008,0),Vector3(0.035,0.016,0.10),"iron")

func wastebasket() -> void:
	hoop(Vector3(0,0.014,0),0.100,0.108,"iron")
	hoop(Vector3(0,0.335,0),0.130,0.138,"steel")
	for index in 20:
		var angle := index*TAU/20
		rod(Vector3(cos(angle)*0.104,0.014,sin(angle)*0.104),Vector3(cos(angle)*0.134,0.335,sin(angle)*0.134),0.0025,"iron")
	for y in [0.12,0.23]:
		var radius: float = 0.104+(y-0.014)*0.030/0.321
		hoop(Vector3(0,y,0),radius-0.0018,radius+0.0018,"iron")
	cylinder(Vector3(0,0.008,0),0.102,0.010,"iron")
	for index in 4: paper_ball(Vector3(-0.04 if index%2==0 else 0.04,0.065+index*0.055,-0.018 if index%2==0 else 0.025),0.048,index)
	collision.append(AABB(Vector3(-0.105,0,-0.105),Vector3(0.21,0.02,0.21)))
	for x in [-0.12,0.12]: collision.append(AABB(Vector3(x-0.02,0.02,-0.12),Vector3(0.04,0.32,0.24)))
	for z in [-0.12,0.12]: collision.append(AABB(Vector3(-0.12,0.02,z-0.02),Vector3(0.24,0.32,0.04)))

func paper_ball(center: Vector3, radius: float, variant: int) -> void:
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sx in [-1,1]:
		for sy in [-1,1]:
			for sz in [-1,1]:
				var a := Vector3(sx,0,0); var b := Vector3(0,sy,0); var c := Vector3(0,0,sz)
				var ab := (a+b).normalized(); var bc := (b+c).normalized(); var ca := (c+a).normalized()
				for triangle in [[a,ab,ca],[ab,b,bc],[ca,bc,c],[ab,bc,ca]]:
					var points := PackedVector3Array()
					for point: Vector3 in triangle: points.append(point*radius*(0.9+0.12*sin(point.x*23+point.y*17+point.z*31+variant)))
					var normal := (points[1]-points[0]).cross(points[2]-points[0]).normalized()
					if normal.dot(points[0])<0: normal=-normal
					for point in points: surface.set_normal(normal); surface.set_uv(Vector2(point.x,point.y)); surface.add_vertex(center+point)
	surface.index(); append(surface.commit(),Transform3D.IDENTITY,"paper")
