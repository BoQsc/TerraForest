extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Assets=preload("res://addons/volumetric_terrain/runtime_assets.gd")
var failures:=0
var evidence:=ProjectSettings.globalize_path("res://reports/road_long_rise_study")
var views:Array[SubViewport]=[]
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
func expected_height(start:Vector3,finish:Vector3,across:float)->float:
	var fraction:=clampf((across-start.x)/(finish.x-start.x),0,1)
	return lerpf(start.y,finish.y,smoothstep(0,1,fraction))
func panel(view:SubViewport,title:String,detail:String)->void:
	var layer:=CanvasLayer.new();view.add_child(layer)
	var background:=PanelContainer.new();background.position=Vector2(20,20)
	var style:=StyleBoxFlat.new();style.bg_color=Color(.025,.045,.055,.92)
	style.content_margin_left=16;style.content_margin_right=16;style.content_margin_top=12;style.content_margin_bottom=12
	background.add_theme_stylebox_override("panel",style);layer.add_child(background)
	var label:=Label.new();label.text=title+"\n"+detail;label.add_theme_font_size_override("font_size",20);background.add_child(label)
func fixture(title:String,length:float,rise:float,offset:float)->Dictionary:
	var view:=SubViewport.new();view.size=Vector2i(960,540);view.own_world_3d=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view);views.append(view)
	var stage:=Node3D.new();view.add_child(stage)
	var core:RefCounted=ClassDB.instantiate("TerrainCore")
	check(Codec.reply_ok(core.execute(Codec.command(6,[1703,Codec.MATERIAL_FIELD_GENERATOR]))),title+": isolated empty field")
	var start:=Vector3(800.5-length*.5,35+offset,800)
	var finish:=start+Vector3(length,rise,0)
	var coefficients:=PackedFloat64Array([-2*rise,3*rise,0,start.y])
	check(Codec.reply_ok(core.execute(Codec.curved_road_bed(start,finish,6,4,4,coefficients,0))),title+": native editable road baked")
	var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
	var faces:=PackedVector3Array()
	var material:=Assets.make_terrain_material()
	for across in range(floori((start.x-8)/16)*16,ceili((finish.x+8)/16)*16,16):
		for depth in [784,800]:
			var decoded:=Codec.decode_mesh(core.build_owned_region(across,depth,16,1,32,64,epoch))
			if decoded.has("error"):check(false,title+": native mesh decode "+str(decoded));return {}
			faces.append_array(decoded.faces)
			if decoded.arrays[Mesh.ARRAY_VERTEX].is_empty():continue
			var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,decoded.arrays)
			var instance:=MeshInstance3D.new();instance.mesh=mesh;instance.material_override=material;stage.add_child(instance)
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
	var collision:=CollisionShape3D.new();var shape:=ConcavePolygonShape3D.new();shape.set_faces(faces);collision.shape=shape;body.add_child(collision);stage.add_child(body)
	var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld")
	check(preload("res://addons/structures/material_startup.gd").prepare(blocks),title+": ordinary building materials")
	stage.add_child(blocks);blocks.set_focus(Vector3(800,36,800));blocks.set_collision_radius(32)
	await physics_frame;await physics_frame
	var rows:Array=[]
	var near_contact:=0
	var large_gap:=0
	var maximum_gap:=0.0
	var maximum_burial:=0.0
	var all_supported:=true
	for across in range(ceili(start.x),floori(finish.x)):
		var surface:=Vector3(across+.5,expected_height(start,finish,across+.5),800.5)
		var fit:Dictionary=blocks.placement_support(AABB(Vector3(across,floorf(surface.y),800),Vector3.ONE),surface,true,true,[])
		all_supported=all_supported and fit.get("ok",false) and fit.hits==9
		if not fit.get("ok",false):continue
		near_contact+=int(fit.gap<=.15);large_gap+=int(fit.gap>.5)
		maximum_gap=maxf(maximum_gap,fit.gap);maximum_burial=maxf(maximum_burial,fit.maximum-fit.bottom)
		rows.append({"x":across,"support":fit})
	check(all_supported,title+": complete collision footprint coverage")
	var center:=Vector3(800.5,expected_height(start,finish,800.5),800.5)
	var contact:Dictionary=blocks.placement_support(AABB(Vector3(800,floorf(center.y),800),Vector3.ONE),center,true,true,[])
	check(contact.get("ok",false),title+": normal grid targeting at midpoint")
	if not contact.get("ok",false):return {}
	var bottom:int=roundi(contact.bottom)
	check(blocks.set_cells(PackedInt32Array([800,bottom,800,1])),title+": separate integer-grid brick")
	blocks.flush_bakes()
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-35,0);sun.shadow_enabled=true;stage.add_child(sun)
	var surroundings:=WorldEnvironment.new();surroundings.environment=Environment.new()
	surroundings.environment.background_mode=Environment.BG_COLOR;surroundings.environment.background_color=Color("91aebc")
	surroundings.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;surroundings.environment.ambient_light_color=Color("d4e0df");surroundings.environment.ambient_light_energy=.6;stage.add_child(surroundings)
	var camera:=Camera3D.new();stage.add_child(camera);camera.position=Vector3(804.3,bottom+1.9,805);camera.look_at(Vector3(800.5,bottom+.2,800.5));camera.current=true;camera.fov=48
	var description:="Middle: %.0f cm gap | %.0f%% of sampled cells within 15 cm"%[contact.gap*100,100.0*near_contact/maxi(1,rows.size())]
	if contact.gap<.001:description="Middle: %.0f cm submerged | %.0f%% of sampled cells within 15 cm"%[(contact.maximum-contact.bottom)*100,100.0*near_contact/maxi(1,rows.size())]
	panel(view,title,description)
	return {"title":title,"length":length,"rise":rise,"offset":offset,"maximum_grade":1.5*rise/length,"samples":rows.size(),"near_contact":near_contact,"large_gap":large_gap,"maximum_gap":maximum_gap,"maximum_burial":maximum_burial,"midpoint":contact,"footprints":rows}
func run()->void:
	DirAccess.make_dir_recursive_absolute(evidence)
	var results:Array=[]
	results.append(await fixture("A / One-metre rise over 15 m",15,1,.08))
	results.append(await fixture("B / One-metre rise over 100 m",100,1,.08))
	results.append(await fixture("C / Near-level street: 10 cm rise over 100 m",100,.1,.05))
	results.append(await fixture("D / Level street: 8 cm above the block grid",100,0,.08))
	if results.any(func(result:Dictionary)->bool:return result.is_empty()):quit(1);return
	check(results[1].maximum_grade<.016 and results[1].midpoint.gap>.35,"barely perceptible long rise still has a large mid-level gap")
	check(absf(results[0].midpoint.gap-results[1].midpoint.gap)<.06,"lengthening a rise does not remove its fractional-height mismatch")
	check(results[2].near_contact==results[2].samples and results[2].maximum_gap<.001 and results[2].maximum_burial<=.16,"gentle near-level stretch stays slightly submerged throughout")
	check(results[3].near_contact==results[3].samples and results[3].maximum_gap<.001 and results[3].maximum_burial<=.09,"eight-centimetre integer-height landing keeps exact grid contact")
	FileAccess.open(evidence.path_join("measurements.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"scope":"Isolated actual native road meshes/collision and block placement; no saved world or production generation modified.","cases":results},"  "))
	if DisplayServer.get_name()!="headless":
		var comparison:=SubViewport.new();comparison.size=Vector2i(1920,1080);comparison.disable_3d=true;comparison.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(comparison)
		for index in views.size():
			var picture:=TextureRect.new();picture.texture=views[index].get_texture();picture.position=Vector2((index%2)*960,(index/2)*540);picture.size=Vector2(960,540);comparison.add_child(picture)
		for frame in 30:await process_frame
		await RenderingServer.frame_post_draw
		check(comparison.get_texture().get_image().save_png(evidence.path_join("comparison.png"))==OK,"actual engine comparison rendered")
		comparison.free()
	for view:SubViewport in views:view.free()
	await process_frame
	print("ROAD_LONG_RISE_STUDY failures=",failures)
	quit(1 if failures else 0)
