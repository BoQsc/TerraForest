# SPDX-License-Identifier: 0BSD
extends SceneTree
const Rails=preload("res://addons/structures/mine_rail_catalog.gd")
func box(surface:SurfaceTool,size:Vector3,pose:Transform3D)->void:
	var primitive:=BoxMesh.new();primitive.size=size;surface.append_from(primitive,0,pose)
func path(part:String,t:float)->Vector3:
	if part in ["straight","short"]:return Vector3(0,0,t*(2 if part=="short" else 4))
	var angle:=t*(PI*.5 if part=="curve" else PI*.25)
	return Vector3(4*(cos(angle)-1),0,4*sin(angle))
func tangent(part:String,t:float)->Vector3:
	if part in ["straight","short"]:return Vector3.BACK
	var angle:=t*(PI*.5 if part=="curve" else PI*.25)
	return Vector3(-sin(angle),0,cos(angle))
func bake(part:String)->Error:
	var steel:=SurfaceTool.new();steel.begin(Mesh.PRIMITIVE_TRIANGLES)
	var timber:=SurfaceTool.new();timber.begin(Mesh.PRIMITIVE_TRIANGLES)
	var curve:bool=part in ["curve","eighth"]
	var length:float=TAU if part=="curve" else PI if part=="eighth" else 2 if part=="short" else 4
	var segments:=24 if part=="curve" else 12 if part=="eighth" else 1
	var proxies:Array[AABB]=[]
	for side:float in [-.5,.5]:
		for index in segments:
			var a:=float(index)/segments;var b:=float(index+1)/segments
			var start:=path(part,a)+Vector3.UP.cross(tangent(part,a))*side
			var finish:=path(part,b)+Vector3.UP.cross(tangent(part,b))*side
			var axis:=(finish-start).normalized();var basis:=Basis(Vector3.UP.cross(axis),Vector3.UP,axis)
			# Distinct foot, web and head give a readable railway profile.
			for profile in [Vector3(.15,.025,.073),Vector3(.045,.075,.11),Vector3(.09,.035,.165)]:
				box(steel,Vector3(profile.x,profile.y,start.distance_to(finish)),Transform3D(basis,(start+finish)*.5+Vector3.UP*profile.z))
	var ties:=ceili(length/.65)
	for index in ties:
		var t:=(index+.5)/ties;var axis:=tangent(part,t)
		box(timber,Vector3(1.55,.06,.24),Transform3D(Basis(Vector3.UP.cross(axis),Vector3.UP,axis),path(part,t)+Vector3.UP*.03))
	# Low walkable proxies, inset at joins; curve proxies follow the bend.
	var pieces:=8 if curve else 1
	for index in pieces:
		var a:=path(part,float(index)/pieces);var b:=path(part,float(index+1)/pieces)
		var bounds:=AABB(a.min(b)-Vector3(.55,0,.0),a.max(b)-a.min(b)+Vector3(1.1,.18,0))
		if curve:
			var axis:=tangent(part,(index+.5)/pieces);var across:=Vector3.UP.cross(axis).abs()*.56
			bounds=AABB(a.min(b)-across,a.max(b)-a.min(b)+across*2+Vector3.UP*.18)
		bounds.position+=Vector3(.015,0,.015);bounds.size-=Vector3(.03,0,.03)
		if part=="curve":
			var end:=bounds.end
			bounds.position.x=maxf(bounds.position.x,-3.985);bounds.position.z=maxf(bounds.position.z,.015)
			bounds.size=end-bounds.position
		proxies.append(bounds)
	if part=="eighth":
		# A broad rotated AABB projects past a diagonal joint. Follow the two
		# actual rail heads here, with 8 cm end clearance, plus interior ties.
		# This remains below the native 32-shape cap and permits paired bends.
		proxies.clear()
		for side:float in [-.5,.5]:
			for index in 12:
				var a:=float(index)/12+(.08/PI if index==0 else 0.0)
				var b:=float(index+1)/12-(.08/PI if index==11 else 0.0)
				var start:=path(part,a)+Vector3.UP.cross(tangent(part,a))*side
				var finish:=path(part,b)+Vector3.UP.cross(tangent(part,b))*side
				proxies.append(AABB(start.min(finish)-Vector3(.035,0,.035),start.max(finish)-start.min(finish)+Vector3(.07,.18,.07)))
		for index in range(1,ties-1):
			var t:=(index+.5)/ties;var axis:=tangent(part,t)
			var pose:=Transform3D(Basis(Vector3.UP.cross(axis),Vector3.UP,axis),path(part,t))
			proxies.append(pose*AABB(Vector3(-.775,0,-.12),Vector3(1.55,.06,.24)))
	var metal:=StandardMaterial3D.new();metal.albedo_color=Color("55514b");metal.metallic=.7;metal.roughness=.55;steel.set_material(metal)
	var wood:=StandardMaterial3D.new();wood.albedo_color=Color("493426");wood.roughness=.95;timber.set_material(wood)
	var mesh:=steel.commit();timber.commit(mesh);mesh.resource_name=Rails.PARTS[part]
	mesh.set_meta("collision_parts",proxies);mesh.set_meta("start",Vector3.ZERO);mesh.set_meta("finish",path(part,1));mesh.set_meta("exit_tangent",tangent(part,1));mesh.set_meta("gauge",1.0)
	return ResourceSaver.save(mesh,"res://addons/structures/prefabs/mine_rail_"+part+".res")
func _initialize()->void:
	for part:String in Rails.PARTS:
		if part=="turnout":continue
		var error:=bake(part)
		if error!=OK:push_error("Rail bake failed: "+part);quit(1);return
	var straight:=Rails.mesh("straight");var curve:=Rails.mesh("curve")
	var transform:=Transform3D(Basis(Vector3.UP,PI*.5),Vector3(-4,0,0))
	var combined:=ArrayMesh.new()
	for index in straight.get_surface_count():
		var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.append_from(straight,index,Transform3D.IDENTITY);surface.append_from(curve,index,transform)
		surface.set_material(straight.surface_get_material(index));surface.commit(combined)
	var proxies:Array=straight.get_meta("collision_parts").duplicate()
	for bounds:AABB in curve.get_meta("collision_parts"):proxies.append(transform*bounds)
	combined.set_meta("collision_parts",proxies);combined.set_meta("start",Vector3.ZERO);combined.set_meta("finish",Vector3(0,0,4));combined.set_meta("exit_tangent",Vector3.BACK);combined.set_meta("gauge",1.0)
	if ResourceSaver.save(combined,"res://addons/structures/prefabs/mine_rail_turnout.res")!=OK:quit(1);return
	var coal:=SurfaceTool.new();coal.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 10:
		var a:=TAU*i/10.;var b:=TAU*(i+1)/10.
		var p:=Vector3(cos(a)*.8,0,sin(a)*.7);var q:=Vector3(cos(b)*.8,0,sin(b)*.7)
		var r:=Vector3(cos(a+.13)*.44,.45+(i%3)*.07,sin(a+.13)*.38)
		var s:=Vector3(cos(b+.13)*.44,.45+((i+1)%3)*.07,sin(b+.13)*.38)
		for vertex:Vector3 in [p,r,q,q,r,s,r,Vector3(.05,.72,-.04),s]:coal.add_vertex(vertex)
	coal.generate_normals()
	var carbon:=StandardMaterial3D.new();carbon.albedo_color=Color("15191c");carbon.metallic=.22;carbon.roughness=.6;coal.set_material(carbon)
	if ResourceSaver.save(coal.commit(),"res://addons/structures/prefabs/coal_heap.res")!=OK:quit(1);return
	print("MINE_RAIL_BAKE passed");quit()
