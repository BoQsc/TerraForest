# SPDX-License-Identifier: 0BSD
extends "res://addons/structures/packs/homestead_10/author.gd"
## Original outdoor geometry; shared offline primitive/cushion/profile helpers.
func _init() -> void:
	super()
	for material: Material in materials.values(): material.resource_name=material.resource_name.replace("Homestead 10","Outdoor 01")
	var palette := {"cardboard":"aa8558","tape":"c4b18a","paper":"ddd9c6","canvas":"647363","seam":"8c9276","refuse":"343d3d","bin":"597966","rusted":"96664e","nest":"8e7146"}
	for label: String in palette:
		var material := StandardMaterial3D.new(); material.resource_name="Outdoor 01 / "+label; material.albedo_color=Color(palette[label]); material.roughness=.93; material.cull_mode=BaseMaterial3D.CULL_DISABLED
		materials[label]=material
	materials.canvas.albedo_texture=texture(true)
	materials.rubber.albedo_color=Color("242827")
	materials.steel.albedo_color=Color("9ca5a0"); materials.steel.roughness=.72

func build(slug: String) -> ArrayMesh:
	surfaces.clear(); collision.clear(); wall_points.clear()
	match slug:
		"bird_nest": bird_nest()
		"duffel_bag": duffel_bag()
		"cardboard_box": cardboard_box(false)
		"open_box": cardboard_box(true)
		"tire": tire(Vector3.ZERO)
		"tire_stack":
			for i in 3: tire(Vector3(0,i*.22,0),i*.25)
		"litter": litter()
		"trash_bag": trash_bag()
		"trash_can": trash_can()
		"dumpster": dumpster()
	var raw := ArrayMesh.new()
	for surface: SurfaceTool in surfaces.values(): surface.index(); surface.commit(raw)
	# Simple rigid props have one tight broad-phase proxy; no per-twig physics.
	if slug not in ["dumpster","trash_can","open_box"]: collision.assign([raw.get_aabb()])
	var pose := Transform3D(Basis.IDENTITY,Vector3(0,-raw.get_aabb().position.y,0)); var mesh := ArrayMesh.new()
	for index in raw.get_surface_count():
		var surface := SurfaceTool.new(); surface.begin(Mesh.PRIMITIVE_TRIANGLES); surface.set_material(raw.surface_get_material(index)); surface.append_from(raw,index,pose); surface.commit(mesh)
	for index in collision.size(): collision[index]=pose*collision[index]
	mesh.resource_name="Outdoor 01 / "+slug; mesh.set_meta("pack_id","terraforest.outdoor_01"); mesh.set_meta("collision_boxes",collision.duplicate()); mesh.set_meta("authored_size",mesh.get_aabb().size)
	return mesh

func bird_nest() -> void:
	lathe([Vector2(0,.012),Vector2(.10,.012),Vector2(.14,.045),Vector2(.12,.065),Vector2(0,.055)],"nest",Vector3.ZERO,24)
	var random := RandomNumberGenerator.new(); random.seed=820
	for level in 13:
		var ring:=PackedVector3Array(); var radius:=.128+level*.005
		for i in 29:
			var angle:=i*TAU/28
			var reach:=radius+random.randf_range(-.007,.007)
			ring.append(Vector3(cos(angle)*reach,.037+level*.009+random.randf_range(-.004,.004),sin(angle)*reach))
		tube(ring,.008,"rope" if level%3==0 else "nest",5)
	for i in 100:
		var angle:=random.randf()*TAU; var radius:=random.randf_range(.13,.19); var level:=random.randf_range(.035,.15)
		var center:=Vector3(cos(angle)*radius,level,sin(angle)*radius); var tangent:=Vector3(-sin(angle),random.randf_range(-.2,.2),cos(angle))
		tube(PackedVector3Array([center-tangent*.065,center,center+tangent*.075]),.006,"rope" if i%3==0 else "nest",5)
	for i in 3: oval(Vector3((i-1)*.037,.089,abs(i-1)*.026),Vector3(.035,.05,.035),"cream")

func torus(center: Vector3, radius: float, thickness: float, material: String) -> void:
	var profile: Array[Vector2]=[]
	for i in 9: profile.append(Vector2(radius+cos(i*TAU/8)*thickness,sin(i*TAU/8)*thickness))
	lathe(profile,material,center,32)

func duffel_bag() -> void:
	padded(Vector3(0,.15,0),Vector3(.70,.30,.34),"canvas")
	for x in [-.22,.22]:
		for z in [-.168,.168]:
			box(Vector3(x,.15,z),Vector3(.033,.25,.012),"seam")
		var points:=PackedVector3Array([Vector3(x,.20,-.145),Vector3(x,.39,-.075),Vector3(x,.43,0),Vector3(x,.39,.075),Vector3(x,.20,.145)])
		tube(points,.012,"seam",6)
	box(Vector3(0,.294,0),Vector3(.55,.012,.012),"iron")
	box(Vector3(.20,.303,0),Vector3(.035,.009,.026),"steel")
	padded(Vector3(0,.14,-.18),Vector3(.25,.13,.035),"canvas")
	box(Vector3(0,.205,-.203),Vector3(.23,.006,.005),"iron")

func cardboard_box(opened: bool) -> void:
	var width:=.54; var depth:=.43; var height:=.39
	box(Vector3(0,.012,0),Vector3(width,.024,depth),"cardboard",true)
	for x in [-1,1]: box(Vector3(x*(width*.5-.01),height*.5,0),Vector3(.02,height,depth),"cardboard",true)
	for z in [-1,1]: box(Vector3(0,height*.5,z*(depth*.5-.01)),Vector3(width,.39,.02),"cardboard",true)
	if opened:
		for x in [-1,1]: box(Vector3(x*.344,.413,0),Vector3(.17,.012,depth),"cardboard",false,Basis(Vector3.FORWARD,x*.25))
		for z in [-1,1]: box(Vector3(0,.415,z*.29),Vector3(width,.012,.17),"cardboard",false,Basis(Vector3.RIGHT,z*.27))
	else:
		box(Vector3(0,height,0),Vector3(width,.02,depth),"cardboard")
		box(Vector3(0,height+.011,0),Vector3(.055,.003,depth+.004),"tape")
		for z in [-1,1]: box(Vector3(0,.33,z*(depth*.5+.002)),Vector3(.055,.14,.003),"tape")
	box(Vector3(.13,.23,-depth*.5-.003),Vector3(.15,.10,.002),"paper")
	for i in 6: box(Vector3(.077+i*.019,.23,-depth*.5-.005),Vector3(.007 if i%2==0 else .011,.062,.002),"iron")
	for x in [-.17,-.12]:
		box(Vector3(x,.25,-depth*.5-.004),Vector3(.008,.07,.002),"iron")
		box(Vector3(x-.008,.285,-depth*.5-.004),Vector3(.026,.006,.002),"iron",false,Basis(Vector3.FORWARD,-.65))

func tire(center: Vector3, angle: float=0) -> void:
	profile_mesh([Vector2(.17,0),Vector2(.27,0),Vector2(.31,.04),Vector2(.32,.08),Vector2(.32,.16),Vector2(.30,.21),Vector2(.18,.22),Vector2(.16,.18),Vector2(.16,.04),Vector2(.17,0)],"rubber",Transform3D(Basis.IDENTITY,center),40)
	for i in 32:
		var turn:=i*TAU/32+angle
		for level in [.065,.155]:
			box(center+Vector3(cos(turn)*.318,level,sin(turn)*.318),Vector3(.018,.044,.062),"refuse",false,Basis(Vector3.UP,-turn)*Basis(Vector3.RIGHT,.20))
	torus(center+Vector3.UP*.216,.205,.004,"refuse")

func litter() -> void:
	var random:=RandomNumberGenerator.new(); random.seed=826
	for i in 6:
		var center:=Vector3(random.randf_range(-.29,.29),.012,random.randf_range(-.22,.22))
		box(center,Vector3(.14,.008,.11),"paper" if i%2 else "cardboard",false,Basis(Vector3.UP,random.randf()*TAU)*Basis(Vector3.RIGHT,random.randf_range(-.12,.12)))
		for j in 3: box(center+Vector3(0,.009,(j-1)*.018),Vector3(.07,.002,.003),"iron")
	for x in [-.18,.18]:
		profile_mesh([Vector2(0,0),Vector2(.031,0),Vector2(.034,.09),Vector2(.031,.10),Vector2(0,.10)],"steel",Transform3D(Basis(Vector3.RIGHT,PI*.5),Vector3(x,.035,.15)),16)
		box(Vector3(x,.06,.19),Vector3(.045,.006,.055),"rusted")

func trash_bag() -> void:
	oval(Vector3(0,.225,0),Vector3(.45,.44,.37),"refuse")
	oval(Vector3(-.075,.31,.025),Vector3(.28,.30,.30),"refuse")
	lathe([Vector2(.13,.35),Vector2(.08,.43),Vector2(.035,.49),Vector2(.055,.53),Vector2(.03,.55)],"refuse")
	torus(Vector3(0,.485,0),.035,.006,"seam")
	for i in 7:
		var angle:=i*TAU/7
		tube(PackedVector3Array([Vector3(cos(angle)*.15,.38,sin(angle)*.13),Vector3(cos(angle)*.06,.44,sin(angle)*.05),Vector3(0,.49,0)]),.005,"rubber",5)

func trash_can() -> void:
	lathe([Vector2(0,0),Vector2(.21,0),Vector2(.23,.52),Vector2(.24,.55),Vector2(.22,.56),Vector2(.20,.51),Vector2(.19,.04),Vector2(0,.04)],"steel",Vector3.ZERO,40)
	for i in 24:
		var angle:=i*TAU/24
		tube(PackedVector3Array([Vector3(cos(angle)*.212,.05,sin(angle)*.212),Vector3(cos(angle)*.228,.50,sin(angle)*.228)]),.005,"steel",5)
	lathe([Vector2(0,.59),Vector2(.13,.59),Vector2(.23,.56),Vector2(.25,.565),Vector2(.25,.58),Vector2(.13,.62),Vector2(0,.62)],"steel")
	tube(PackedVector3Array([Vector3(-.055,.62,0),Vector3(-.05,.67,0),Vector3(.05,.67,0),Vector3(.055,.62,0)]),.012,"iron")
	for x in [-1,1]: tube(PackedVector3Array([Vector3(x*.224,.44,-.045),Vector3(x*.28,.42,-.045),Vector3(x*.28,.42,.045),Vector3(x*.224,.44,.045)]),.008,"iron")
	collision.assign([AABB(Vector3(-.24,0,-.24),Vector3(.48,.62,.48))])

func dumpster() -> void:
	box(Vector3(0,.27,0),Vector3(1.70,.12,.90),"bin",true)
	for x in [-.84,.84]: box(Vector3(x,.72,0),Vector3(.06,.90,.96),"bin",true)
	for z in [-.45,.45]: box(Vector3(0,.72,z),Vector3(1.68,.90,.06),"bin",true)
	for x in [-.57,0,.57]: box(Vector3(x,.70,-.49),Vector3(.045,.69,.035),"bin")
	for x in [-.44,.44]:
		padded(Vector3(x,1.20,0),Vector3(.88,.09,1.01),"rubber")
		for z in [-.30,-.15,0,.15,.30]: box(Vector3(x,1.25,z),Vector3(.66,.025,.035),"refuse")
		box(Vector3(x,1.265,-.40),Vector3(.19,.04,.06),"iron")
	for x in [-.66,.66]:
		for z in [-.32,.32]:
			box(Vector3(x,.19,z),Vector3(.065,.16,.065),"steel")
			profile_mesh([Vector2(0,0),Vector2(.10,0),Vector2(.10,.055),Vector2(0,.055)],"rubber",Transform3D(Basis(Vector3.FORWARD,PI*.5),Vector3(x+.027,.10,z)),20)
	box(Vector3(0,.85,-.484),Vector3(.39,.20,.008),"paper")
	for i in 3: box(Vector3(0,.90-i*.045,-.491),Vector3(.27,.012,.005),"bin")
	for x in [-.85,.85]: tube(PackedVector3Array([Vector3(x,.9,-.16),Vector3(x*1.10,.9,-.16),Vector3(x*1.10,.9,.16),Vector3(x,.9,.16)]),.016,"steel")
	collision.append(AABB(Vector3(-.88,1.15,-.50),Vector3(1.76,.13,1.0)))
