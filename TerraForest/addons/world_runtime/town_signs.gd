# SPDX-License-Identifier: 0BSD
extends Node3D
## Six static signs at most. Native model ownership supplies collision, removal,
## streaming and persistence; lettering changes only on publication/restore/edit.
const Plan=preload("res://addons/world_runtime/town_sign_plan.gd")
const KEY:="wayfinding/town_sign/v1"
static var textures:Dictionary={}
var store:RefCounted
var collection:Node3D
var labels:Dictionary={}
var meshes:Dictionary={}

func prepare(persistence:RefCounted,structures:Node3D)->bool:
	store=ClassDB.instantiate("NativeGeneratedRegion")
	collection=structures.register_model(KEY,body_mesh())
	if collection==null or not collection.configure_compound_collision([
		AABB(Vector3(-1.11,-.4,-.29),Vector3(.14,2.8,.18)),
		AABB(Vector3(.97,-.4,-.29),Vector3(.14,2.8,.18)),
		AABB(Vector3(-1.4,1.45,-.13),Vector3(2.8,.92,.16))],64,16,4,48,12):return false
	structures.object_definitions[KEY]={"name":"Town sign","recipe":{"wood":4,"metal":1},"salvage":{"wood":2},"durability":{"health":90,"material":"wood"}}
	collection.changed.connect(sync_labels)
	return persistence.register_component("town_signs_v1",store.capture_snapshot,restore_snapshot,store,PackedByteArray())

func restore_snapshot(bytes:PackedByteArray)->bool:
	if not store.restore_snapshot(bytes):return false
	sync_labels();return true

func sync_labels()->void:
	for label:Node3D in labels.values():label.queue_free()
	labels.clear()
	if store==null or collection==null:return
	for place:Dictionary in store.get_plan().get("places",[]):
		if labels.size()>=6:break
		var values:PackedFloat32Array=collection.get_instance(place.id)
		if values.size()!=12:continue
		var pose:=Transform3D(Basis(Vector3(values[0],values[4],values[8]),Vector3(values[1],values[5],values[9]),Vector3(values[2],values[6],values[10])),Vector3(values[3],values[7],values[11]))
		var label:=MeshInstance3D.new();label.mesh=lettering(place.title)
		label.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.visibility_range_end=180;label.visibility_range_end_margin=15
		add_child(label);label.transform=pose*Transform3D(Basis.IDENTITY,Vector3(0,1.88,.04))
		labels[place.id]=label

func lettering(title:String)->Mesh:
	if meshes.has(title):return meshes[title]
	var mesh:=TextMesh.new();mesh.text=title.to_upper();mesh.font=ThemeDB.fallback_font
	mesh.font_size=72;mesh.pixel_size=.006;mesh.depth=.002
	var width:float=mesh.get_aabb().size.x
	if width>2.48:mesh.pixel_size*=2.48/width
	var material:=StandardMaterial3D.new();material.albedo_color=Color("d6cfb4");material.roughness=.95
	mesh.material=material;meshes[title]=mesh
	return mesh

static func body_mesh()->ArrayMesh:
	var mesh:=ArrayMesh.new()
	var wood:=StandardMaterial3D.new();wood.albedo_color=Color("b3aa96");wood.roughness=.98
	wood.albedo_texture=material_texture("weathered_timber")
	var paint:=StandardMaterial3D.new();paint.albedo_color=Color("5c6d5b");paint.roughness=.92
	paint.albedo_texture=material_texture("patinated_zinc")
	if wood.albedo_texture==null or paint.albedo_texture==null:return null
	var edge:=StandardMaterial3D.new();edge.albedo_color=Color("958e78");edge.roughness=.95
	var groups:=[
		[wood,[AABB(Vector3(-1.11,-.4,-.29),Vector3(.14,2.8,.18)),AABB(Vector3(.97,-.4,-.29),Vector3(.14,2.8,.18))]],
		[paint,[AABB(Vector3(-1.4,1.45,-.13),Vector3(2.8,.92,.16))]],
		[edge,[AABB(Vector3(-1.35,1.5,.032),Vector3(2.7,.018,.006)),AABB(Vector3(-1.35,2.30,.032),Vector3(2.7,.018,.006)),AABB(Vector3(-1.35,1.5,.032),Vector3(.018,.82,.006)),AABB(Vector3(1.332,1.5,.032),Vector3(.018,.82,.006))]]]
	for group:Array in groups:
		var surface:=SurfaceTool.new();surface.begin(Mesh.PRIMITIVE_TRIANGLES);surface.set_material(group[0])
		for bounds:AABB in group[1]:
			var box:=BoxMesh.new();box.size=bounds.size
			var source:Mesh=box
			if group[0]==wood or group[0]==paint:
				var arrays:Array=box.surface_get_arrays(0)
				var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
				var uvs:=PackedVector2Array()
				for i in vertices.size():
					var vertex:Vector3=vertices[i]
					if group[0]==wood:
						# The approved timber image has horizontal boards. Turn its
						# grain along each post and sample inside one plank, not seams.
						uvs.append(Vector2(vertex.y*.6,.125+(vertex.x if absf(normals[i].z)>.5 else vertex.z)*.5))
					else:
						# One flat painted panel: omit the roofing texture's folded seams.
						uvs.append(Vector2(.25+vertex.x/bounds.size.x*.38,.5+vertex.y/bounds.size.y*.9))
				arrays[Mesh.ARRAY_TEX_UV]=uvs
				var mapped:=ArrayMesh.new();mapped.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);source=mapped
			surface.append_from(source,0,Transform3D(Basis.IDENTITY,bounds.get_center()))
		surface.commit(mesh)
	return mesh

static func material_texture(material_name:String)->Texture2D:
	if textures.has(material_name):return textures[material_name]
	# Reuse the approved E2 image-generated material, retaining its CC0 provenance.
	# Decode once per process; all signs share these two 512 px mipmapped textures.
	var source:=Image.new()
	var path:="res://addons/structures/textures/expansion_v2/"+material_name+".trtex"
	if source.load_png_from_buffer(FileAccess.get_file_as_bytes(path))!=OK:return null
	source.generate_mipmaps();textures[material_name]=ImageTexture.create_from_image(source)
	return textures[material_name]

func publish(game:Node,seed_value:int,generator:int,sites:Array,network:Dictionary)->bool:
	if store.get_plan().get("present",false):return false
	var candidates:Dictionary=Plan.candidates(sites,network)
	var places:Array=[];var identities:=PackedInt64Array();var poses:Array[Transform3D]=[]
	for town:int in candidates:
		var arrivals:Array[Vector3]=[]
		for candidate:Dictionary in candidates[town]:
			var duplicate:=false
			for arrival:Vector3 in arrivals:
				if arrival.distance_to(candidate.approach)<50:duplicate=true;break
			if duplicate:continue
			var pose:Transform3D=candidate.transform
			var probes:=Plan.corners(pose)
			probes.append(pose*Vector3(-1.04,0,-.2));probes.append(pose*Vector3(1.04,0,-.2))
			var sampled:Dictionary=await survey(game.terrain,probes)
			if not sampled.get("ok",false):return false
			if not sampled.supported:continue
			var low:=INF;var high:=-INF;var steep:=false
			for i in sampled.points.size():
				var point:Vector3=sampled.points[i]
				low=minf(low,point.y);high=maxf(high,point.y)
				if not point.is_finite() or sampled.normals[i].y<.90:steep=true
			if steep or high-low>.35 or absf((low+high)*.5-float(candidate.road_height))>3:continue
			pose.origin.y=high
			var water_probes:Array[Transform3D]=[]
			for point:Vector3 in sampled.points:water_probes.append(Transform3D(Basis.IDENTITY,point+Vector3.UP*.05))
			var wet:PackedByteArray=game.lakes.placement_mask(water_probes)
			if wet.size()!=water_probes.size():return false
			if wet.count(0)!=wet.size():continue
			var id:int=places.size()+1
			places.append({"id":id,"title":Plan.town_name(seed_value,town),"detail":"Roadside town entrance","position":pose.origin})
			identities.append(id);poses.append(pose);arrivals.append(candidate.approach)
			if arrivals.size()==2:break
		if arrivals.is_empty():push_error("No grounded roadside sign site for town "+str(town));return false
	if places.is_empty() or not collection.upsert_transforms(identities,poses):return false
	if not store.set_plan(seed_value,generator,places,[]):return false
	sync_labels();return true

func survey(terrain:Node,points:PackedVector3Array)->Dictionary:
	# Query the edited density field. Vegetation's natural-root surface sampler
	# deliberately rejects graded roots and is not a ground-placement contract.
	var tokens:Dictionary={};var replies:Dictionary={}
	var receive:=func(reply:Dictionary):
		if tokens.has(reply.token):replies[tokens[reply.token]]=reply
	terrain.density_ray_received.connect(receive)
	var deadline:=Time.get_ticks_msec()+10000
	for i in points.size():
		var token:int=preload("res://addons/volumetric_terrain/surface_tokens.gd").allocate();tokens[token]=i
		var top:=Vector3(points[i].x,minf(249,points[i].y+8),points[i].z)
		var bottom:=Vector3(points[i].x,maxf(1,points[i].y-8),points[i].z)
		while not terrain.request_density_ray(top,bottom,token,64):
			if Time.get_ticks_msec()>deadline:terrain.density_ray_received.disconnect(receive);return {}
			await get_tree().process_frame
	while replies.size()!=points.size() and Time.get_ticks_msec()<deadline:await get_tree().process_frame
	terrain.density_ray_received.disconnect(receive)
	if replies.size()!=points.size():return {}
	var surface:=PackedVector3Array();var normals:=PackedVector3Array()
	for i in points.size():
		var reply:Dictionary=replies[i]
		if reply.status=="miss":return {"ok":true,"supported":false}
		if reply.status!="hit":return {}
		surface.append(reply.position);normals.append(reply.normal)
	return {"ok":true,"supported":true,"points":surface,"normals":normals}
