# SPDX-License-Identifier: 0BSD
extends RefCounted
## Original editable geometry; offline authoring only.
const PACK_ID := "terraforest.homestead_02"
var materials: Dictionary = {}
var surfaces: Dictionary = {}
var collision: Array[AABB] = []
var wall_points := PackedVector3Array()

func _init() -> void:
	var palette := {"wood":"70503c","edge":"b28a58","teal":"527975","linen":"d8ccaa","fabric":"688582","iron":"303a3d","brass":"b79b62","rust":"a96349","sky":"96b3b3","hill":"52715f","pine":"314e49","sun":"dfb46b"}
	for label: String in palette:
		var material := StandardMaterial3D.new()
		material.resource_name = "Homestead 02 / " + label
		material.albedo_color = Color(palette[label]); material.roughness = 0.88
		if label in ["wood","edge","teal","fabric","linen"]: material.albedo_texture = texture(label in ["fabric","linen"])
		if label in ["iron","brass"]: material.metallic = 0.65; material.roughness = 0.42
		if label == "fabric": material.cull_mode = BaseMaterial3D.CULL_DISABLED
		if label in ["sky","hill","pine","sun"]: material.cull_mode=BaseMaterial3D.CULL_DISABLED; material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		materials[label] = material
	var glass := StandardMaterial3D.new(); glass.resource_name="Homestead 02 / amber glass"
	glass.albedo_color=Color(0.62,0.28,0.055,0.52); glass.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA; glass.cull_mode=BaseMaterial3D.CULL_DISABLED; glass.roughness=0.14
	materials.glass=glass
	var ceramic := StandardMaterial3D.new(); ceramic.resource_name="Homestead 02 / cream ceramic"; ceramic.albedo_color=Color("e3d9be"); ceramic.roughness=0.30; materials.ceramic=ceramic
	var bulb := StandardMaterial3D.new(); bulb.resource_name="Homestead 02 / warm bulb"; bulb.albedo_color=Color("ffe4b0"); bulb.emission_enabled=true; bulb.emission=Color("ffd6a0"); bulb.emission_energy_multiplier=0.65; materials.bulb=bulb

func texture(fabric: bool) -> ImageTexture:
	var pixels := Image.create(128,128,false,Image.FORMAT_RGB8)
	var random := RandomNumberGenerator.new(); random.seed=170302
	for y in 128:
		for x in 128:
			var value: float = 0.88+0.065*float((x+y)%2)+random.randf()*0.035 if fabric else 0.85+0.07*sin(x*0.52+1.3*sin(y*0.07))+0.04*sin(x*1.8+y*0.013)+random.randf()*0.035
			pixels.set_pixel(x,y,Color(value,value,value))
	return ImageTexture.create_from_image(pixels)

func append(mesh: Mesh, pose: Transform3D, material: String) -> void:
	if not surfaces.has(material):
		var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); surface.set_material(materials[material]); surfaces[material]=surface
	surfaces[material].append_from(mesh,0,pose)

func box(center: Vector3, size: Vector3, material: String, solid: bool=false, basis: Basis=Basis.IDENTITY) -> void:
	var mesh := BoxMesh.new(); mesh.size=size
	append(mesh,Transform3D(basis,center),material)
	if solid: collision.append(Transform3D(basis,center)*AABB(-size*0.5,size))

func cylinder(center: Vector3, radius: float, height: float, material: String, direction: Vector3=Vector3.UP) -> void:
	var mesh := CylinderMesh.new(); mesh.top_radius=radius; mesh.bottom_radius=radius; mesh.height=height; mesh.radial_segments=24; mesh.rings=1
	var basis := Basis(Quaternion(Vector3.UP,direction.normalized()))
	append(mesh,Transform3D(basis,center),material)

func rod(start: Vector3, end: Vector3, radius: float, material: String) -> void:
	cylinder((start+end)*0.5,radius,start.distance_to(end),material,end-start)

func sphere(center: Vector3, radius: float, material: String) -> void:
	var mesh := SphereMesh.new(); mesh.radius=radius; mesh.height=radius*2; mesh.radial_segments=16; mesh.rings=8
	append(mesh,Transform3D(Basis.IDENTITY,center),material)

func lathe(profile: Array[Vector2], material: String, offset: Vector3=Vector3.ZERO, segments: int=32) -> void:
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in segments:
		var a := segment*TAU/segments; var b := (segment+1)*TAU/segments
		for index in profile.size()-1:
			var p := profile[index]; var q := profile[index+1]
			var points := [Vector3(p.x*cos(a),p.y,p.x*sin(a)),Vector3(p.x*cos(b),p.y,p.x*sin(b)),Vector3(q.x*cos(b),q.y,q.x*sin(b)),Vector3(q.x*cos(a),q.y,q.x*sin(a))]
			for corner in [0,2,1,0,3,2]: surface.set_uv(Vector2(points[corner].x,points[corner].y)); surface.add_vertex(points[corner]+offset)
	surface.generate_normals(); surface.index(); append(surface.commit(),Transform3D.IDENTITY,material)

func polygon(points: PackedVector3Array, material: String) -> void:
	var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(1,points.size()-1):
		for corner in [0,index+1,index]: surface.set_uv(Vector2(points[corner].x,points[corner].y)); surface.add_vertex(points[corner])
	surface.generate_normals(); surface.index(); append(surface.commit(),Transform3D.IDENTITY,material)

func hoop(center: Vector3, inner: float, outer: float, material: String, basis: Basis=Basis.IDENTITY) -> void:
	var mesh := TorusMesh.new(); mesh.inner_radius=inner; mesh.outer_radius=outer; mesh.rings=32; mesh.ring_segments=8
	append(mesh,Transform3D(basis,center),material)

func build(slug: String) -> ArrayMesh:
	surfaces.clear(); collision.clear(); wall_points.clear()
	match slug:
		"rug": rug()
		"curtains": curtains()
		"picture": picture()
		"clock": clock()
		"coat_rack": coat_rack()
		"basket": basket()
		"crate": crate()
		"bottle": bottle()
		"dishes": dishes()
		"lamp": lamp()
	var mesh := ArrayMesh.new()
	for surface: SurfaceTool in surfaces.values(): surface.index(); surface.commit(mesh)
	mesh.resource_name="Homestead 02 / "+slug
	mesh.set_meta("pack_id",PACK_ID); mesh.set_meta("collision_boxes",collision.duplicate()); mesh.set_meta("authored_size",mesh.get_aabb().size)
	if not wall_points.is_empty(): mesh.set_meta("wall_support_points",wall_points)
	return mesh

func rug() -> void:
	box(Vector3(0,0.009,0),Vector3(2.2,0.018,1.5),"fabric",true)
	for x in [-1.02,1.02]: box(Vector3(x,0.020,0),Vector3(0.10,0.006,1.5),"linen")
	for z in [-0.67,0.67]: box(Vector3(0,0.020,z),Vector3(2.2,0.006,0.10),"linen")
	for x in [-0.66,-0.33,0.0,0.33,0.66]:
		box(Vector3(x,0.024,0),Vector3(0.19,0.005,0.19),"rust",false,Basis(Vector3.UP,PI*0.25))
		box(Vector3(x,0.027,0),Vector3(0.085,0.004,0.085),"linen",false,Basis(Vector3.UP,PI*0.25))
	for x in range(-10,11):
		for z in [-0.775,0.775]: cylinder(Vector3(x*0.10,0.012,z),0.006,0.07,"linen",Vector3.BACK)

func curtains() -> void:
	cylinder(Vector3(0,1.76,-0.08),0.024,2.20,"iron",Vector3.RIGHT)
	for x in [-1.12,1.12]: sphere(Vector3(x,1.76,-0.08),0.045,"brass")
	for x in [-1.02,1.02]:
		box(Vector3(x,1.73,0.03),Vector3(0.055,0.075,0.18),"iron",true)
		wall_points.append(Vector3(x,1.73,0.12))
	for side in [-1,1]:
		var low := -0.99 if side == -1 else 0.34
		for strip in 20:
			var x0: float=low+strip*0.0325; var x1: float=x0+0.0325
			var z0 := -0.10-0.055*cos(strip*TAU/5.0); var z1 := -0.10-0.055*cos((strip+1)*TAU/5.0)
			var bottom0 := 0.08+0.025*cos(strip*TAU/5.0); var bottom1 := 0.08+0.025*cos((strip+1)*TAU/5.0)
			polygon(PackedVector3Array([Vector3(x0,bottom0,z0),Vector3(x1,bottom1,z1),Vector3(x1,1.68,z1),Vector3(x0,1.68,z0)]),"fabric")
			rod(Vector3(x0,bottom0,z0),Vector3(x1,bottom1,z1),0.009,"linen")
		for index in 7:
			var x: float=low+0.045+index*0.093
			hoop(Vector3(x,1.73,-0.08),0.027,0.034,"brass",Basis(Vector3.FORWARD,PI*0.5))
		collision.append(AABB(Vector3(low,0.05,-0.17),Vector3(0.65,1.65,0.14)))

func picture() -> void:
	box(Vector3(0,0.31,0),Vector3(0.78,0.56,0.035),"wood",true)
	box(Vector3(0,0.31,-0.026),Vector3(0.66,0.44,0.015),"sky")
	for x in [-0.365,0.365]: box(Vector3(x,0.31,-0.034),Vector3(0.05,0.60,0.065),"edge")
	for y in [0.035,0.585]: box(Vector3(0,y,-0.034),Vector3(0.78,0.05,0.065),"edge")
	polygon(PackedVector3Array([Vector3(-0.33,0.09,-0.038),Vector3(0.33,0.09,-0.038),Vector3(0.33,0.32,-0.038),Vector3(0.12,0.43,-0.038),Vector3(-0.10,0.26,-0.038),Vector3(-0.33,0.37,-0.038)]),"hill")
	polygon(PackedVector3Array([Vector3(-0.33,0.09,-0.042),Vector3(0.33,0.09,-0.042),Vector3(0.33,0.20,-0.042),Vector3(0.05,0.29,-0.042),Vector3(-0.14,0.17,-0.042),Vector3(-0.33,0.24,-0.042)]),"pine")
	cylinder(Vector3(0.17,0.43,-0.045),0.041,0.004,"sun",Vector3.FORWARD)
	for x in [-0.24,-0.15]:
		box(Vector3(x,0.19,-0.048),Vector3(0.012,0.15,0.005),"wood")
		polygon(PackedVector3Array([Vector3(x-0.045,0.19,-0.053),Vector3(x+0.045,0.19,-0.053),Vector3(x,0.34,-0.053)]),"pine")
	for x in [-0.28,0.28]:
		for y in [0.11,0.51]: wall_points.append(Vector3(x,y,0.018))

func clock() -> void:
	cylinder(Vector3(0,0.225,0),0.22,0.065,"wood",Vector3.FORWARD)
	cylinder(Vector3(0,0.225,-0.040),0.192,0.015,"ceramic",Vector3.FORWARD)
	hoop(Vector3(0,0.225,-0.05),0.19,0.207,"brass",Basis(Vector3.RIGHT,PI*0.5))
	for index in 12:
		var angle := index*TAU/12.0
		box(Vector3(sin(angle)*0.163,0.225+cos(angle)*0.163,-0.052),Vector3(0.009,0.024,0.006),"iron",false,Basis(Vector3.FORWARD,angle))
	rod(Vector3(0,0.225,-0.060),Vector3(-0.07,0.285,-0.060),0.008,"iron")
	rod(Vector3(0,0.225,-0.066),Vector3(0.10,0.335,-0.066),0.006,"iron")
	sphere(Vector3(0,0.225,-0.070),0.014,"brass")
	wall_points=PackedVector3Array([Vector3(0,0.35,0.033),Vector3(-0.12,0.14,0.033),Vector3(0.12,0.14,0.033)])
	collision.append(AABB(Vector3(-0.22,0.005,-0.055),Vector3(0.44,0.44,0.088)))

func coat_rack() -> void:
	cylinder(Vector3(0,0.82,0),0.035,1.60,"wood")
	for index in 3:
		var angle := index*TAU/3.0
		var end := Vector3(cos(angle)*0.31,0.045,sin(angle)*0.31)
		rod(Vector3(0,0.22,0),end,0.028,"wood"); sphere(end,0.034,"edge")
	for index in 6:
		var angle := index*TAU/6.0
		var start := Vector3(0,1.48,0); var end := Vector3(cos(angle)*0.20,1.72,sin(angle)*0.20)
		rod(start,end,0.017,"brass"); sphere(end,0.026,"edge")
	sphere(Vector3(0,1.66,0),0.05,"edge")
	collision.append(AABB(Vector3(-0.04,0.03,-0.04),Vector3(0.08,1.66,0.08)))
	collision.append(AABB(Vector3(-0.27,0,-0.27),Vector3(0.54,0.22,0.54)))
	collision.append(AABB(Vector3(-0.23,1.46,-0.23),Vector3(0.46,0.29,0.46)))

func basket() -> void:
	box(Vector3(0,0.025,0),Vector3(0.50,0.05,0.36),"edge",true)
	for layer in 10:
		var y := 0.055+layer*0.032
		for z in [-0.18,0.18]: box(Vector3(0,y,z),Vector3(0.52,0.019,0.025),"edge" if layer%2==0 else "wood")
		for x in [-0.25,0.25]: box(Vector3(x,y,0),Vector3(0.025,0.019,0.36),"edge" if layer%2==0 else "wood")
	for index in 13:
		for z in [-0.183,0.183]: box(Vector3(-0.24+index*0.04,0.20,z),Vector3(0.012,0.34,0.023),"linen")
	for index in 9:
		for x in [-0.253,0.253]: box(Vector3(x,0.20,-0.16+index*0.04),Vector3(0.023,0.34,0.012),"linen")
	for z in [-0.18,0.18]: box(Vector3(0,0.38,z),Vector3(0.54,0.035,0.035),"edge",true)
	for x in [-0.25,0.25]:
		box(Vector3(x,0.38,0),Vector3(0.035,0.035,0.39),"edge",true)
		hoop(Vector3(x,0.40,0),0.068,0.085,"edge",Basis(Vector3.FORWARD,PI*0.5))
	for z in [-0.18,0.18]: collision.append(AABB(Vector3(-0.26,0.04,z-0.02),Vector3(0.52,0.34,0.04)))
	for x in [-0.25,0.25]: collision.append(AABB(Vector3(x-0.02,0.04,-0.18),Vector3(0.04,0.34,0.36)))

func crate() -> void:
	for index in 5: box(Vector3(-0.24+index*0.12,0.025,0),Vector3(0.108,0.05,0.44),"wood")
	for level in 3:
		var y := 0.095+level*0.12
		for z in [-0.22,0.22]: box(Vector3(0,y,z),Vector3(0.62,0.092,0.035),"edge")
		for x in [-0.29,0.29]: box(Vector3(x,y,0),Vector3(0.035,0.092,0.42),"wood")
	for x in [-0.27,0.27]:
		for z in [-0.20,0.20]: box(Vector3(x,0.20,z),Vector3(0.055,0.40,0.055),"wood")
	for z in [-0.22,0.22]:
		for x in [-0.23,0.23]: box(Vector3(x,0.415,z),Vector3(0.16,0.07,0.035),"edge")
		box(Vector3(0,0.46,z),Vector3(0.62,0.04,0.035),"edge")
		collision.append(AABB(Vector3(-0.31,0.04,z-0.02),Vector3(0.62,0.44,0.04)))
	for x in [-0.29,0.29]: collision.append(AABB(Vector3(x-0.02,0.04,-0.22),Vector3(0.04,0.40,0.44)))
	collision.append(AABB(Vector3(-0.31,0,-0.24),Vector3(0.62,0.05,0.48)))

func bottle() -> void:
	lathe([Vector2(0,0.008),Vector2(0.065,0.008),Vector2(0.074,0.025),Vector2(0.074,0.23),Vector2(0.03,0.285),Vector2(0.027,0.36),Vector2(0.020,0.36),Vector2(0.021,0.29),Vector2(0.066,0.225),Vector2(0.066,0.022),Vector2(0,0.022)],"glass")
	cylinder(Vector3(0,0.364,0),0.022,0.045,"wood")
	hoop(Vector3(0,0.349,0),0.021,0.031,"glass")
	box(Vector3(0,0.15,-0.074),Vector3(0.089,0.082,0.004),"linen")
	box(Vector3(0,0.15,-0.077),Vector3(0.058,0.008,0.002),"rust")
	collision.append(AABB(Vector3(-0.074,0,-0.078),Vector3(0.148,0.387,0.152)))

func dishes() -> void:
	for layer in 2:
		var offset := Vector3(-0.10,layer*0.019,0)
		lathe([Vector2(0,0.008),Vector2(0.10,0.008),Vector2(0.16,0.032),Vector2(0.17,0.042),Vector2(0.16,0.048),Vector2(0.10,0.024),Vector2(0,0.024)],"ceramic",offset)
		hoop(offset+Vector3(0,0.045,0),0.151,0.158,"teal")
	lathe([Vector2(0,0.008),Vector2(0.055,0.008),Vector2(0.12,0.10),Vector2(0.125,0.13),Vector2(0.115,0.135),Vector2(0.108,0.104),Vector2(0.047,0.024),Vector2(0,0.024)],"ceramic",Vector3(0.20,0,0.025))
	hoop(Vector3(0.20,0.132,0.025),0.114,0.125,"teal")
	collision.append(AABB(Vector3(-0.27,0,-0.17),Vector3(0.595,0.14,0.34)))

func lamp() -> void:
	lathe([Vector2(0,0.005),Vector2(0.14,0.005),Vector2(0.14,0.025),Vector2(0.12,0.055),Vector2(0.055,0.065),Vector2(0,0.065)],"brass")
	cylinder(Vector3(0,0.23,0),0.022,0.34,"iron")
	sphere(Vector3(0,0.48,0),0.048,"bulb")
	lathe([Vector2(0.21,0.32),Vector2(0.225,0.32),Vector2(0.13,0.63),Vector2(0.116,0.63),Vector2(0.21,0.32)],"linen")
	for values in [Vector3(0.216,0.32,0.225),Vector3(0.121,0.63,0.132)]: hoop(Vector3(0,values.y,0),values.x,values.z,"teal")
	for index in 12:
		var angle := index*TAU/12.0
		rod(Vector3(cos(angle)*0.223,0.325,sin(angle)*0.223),Vector3(cos(angle)*0.129,0.625,sin(angle)*0.129),0.0025,"linen")
	collision.append(AABB(Vector3(-0.14,0,-0.14),Vector3(0.28,0.32,0.28)))
	collision.append(AABB(Vector3(-0.225,0.32,-0.225),Vector3(0.45,0.32,0.45)))
