# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var fractures:Node3D
var camera:Camera3D
var output:="res://reports/boulder_fracture_cache"
var movie:=false
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func picture(name:String)->void:
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func motion_clip()->void:
	var folder:=output.path_join("motion");DirAccess.make_dir_recursive_absolute(folder)
	var timing:Array=[];var began:=Time.get_ticks_msec()
	for i in 36:
		await process_frame;await RenderingServer.frame_post_draw
		timing.append(Time.get_ticks_msec()-began)
		root.get_texture().get_image().save_png(folder.path_join("%03d.png"%i))
		await create_timer(.025).timeout
	var file:=FileAccess.open(folder.path_join("timing.json"),FileAccess.WRITE);file.store_string(JSON.stringify(timing));file.close()
func closed_mesh(mesh:Mesh,expected:int)->bool:
	var arrays:Array=mesh.surface_get_arrays(0);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2];var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
	var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	if indices.is_empty():
		for i in vertices.size():indices.append(i)
	var pieces:Dictionary={}
	for i in range(0,indices.size(),3):
		var key:=str(uv[indices[i]].snapped(Vector2.ONE*.0001))+":"+str(snappedf(colors[indices[i]].b,.0001))
		if not pieces.has(key):pieces[key]={}
		for j in 3:
			var a:=str(vertices[indices[i+j]].snapped(Vector3.ONE*.00001));var b:=str(vertices[indices[i+(j+1)%3]].snapped(Vector3.ONE*.00001))
			if a==b:continue
			var edge:=a+"/"+b if a<b else b+"/"+a
			pieces[key][edge]=int(pieces[key].get(edge,0))+1
	if pieces.size()!=expected:print("PIECE_COUNT ",pieces.size()," expected=",expected);return false
	for piece:Dictionary in pieces.values():
		for edge:String in piece:
			if piece[edge]!=2:print("OPEN_EDGE count=",piece[edge]," ",edge);return false
	return true
func upright_chunks(mesh:Mesh)->bool:
	var arrays:Array=mesh.surface_get_arrays(0);var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var centres:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2];var pieces:Dictionary={}
	for i in vertices.size():
		var key:=str(centres[i].snapped(Vector2.ONE*.0001))
		pieces[key]=pieces[key].expand(vertices[i]) if pieces.has(key) else AABB(vertices[i],Vector3.ZERO)
	for box:AABB in pieces.values():
		if box.size.y<0.175:print("THIN_LAYER ",box);return false
	return true
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--fracture-evidence="):output=arg.trim_prefix("--fracture-evidence=")
		if arg=="--motion-preview":movie=true
	DirAccess.make_dir_recursive_absolute(output)
	for addon:String in ["player_runtime","vegetation_runtime"]:GDExtensionManager.load_extension("res://addons/%s/%s.gdextension"%[addon,addon])
	var world:=Node3D.new();root.add_child(world)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("9dbac5");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.65;world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-50,-30,0);light.shadow_enabled=true;world.add_child(light)
	var floor:=StaticBody3D.new();world.add_child(floor);floor.collision_layer=1
	var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=Vector3(40,1,40);shape.position.y=-.5;floor.add_child(shape)
	var ground:=MeshInstance3D.new();ground.mesh=PlaneMesh.new();ground.mesh.size=Vector2(40,40);var ground_material:=StandardMaterial3D.new();ground_material.albedo_color=Color("49634a");ground.mesh.material=ground_material;world.add_child(ground)
	camera=Camera3D.new();camera.position=Vector3(8,6,10);world.add_child(camera);camera.look_at(Vector3(0,1,0));camera.current=true
	var damage:RefCounted=ClassDB.instantiate("NativeWorldDurability")
	var geometry:Mesh=preload("res://addons/world_ecosystem/woodland_mesh.gd").build(0)
	var material:ShaderMaterial=preload("res://addons/world_ecosystem/boulder_material.tres").duplicate()
	fractures=ClassDB.instantiate("NativeBoulderFracture");world.add_child(fractures)
	check(fractures.configure(geometry,material,damage),"shared native fracture cache initializes")
	for stage in range(1,4):check(closed_mesh(fractures.stage_mesh(stage),1<<stage) and upright_chunks(fractures.stage_mesh(stage)),"stage %d has %d closed upright chunks"%[stage,1<<stage])
	if "--dump-geometry" in OS.get_cmdline_user_args():
		var arrays:Array=fractures.stage_mesh(3).surface_get_arrays(0);var data:Array=[]
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV2];var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
		for i in vertices.size():data.append([vertices[i].x,vertices[i].y,vertices[i].z,uv[i].x,uv[i].y,colors[i].b])
		var file:=FileAccess.open(output.path_join("geometry.json"),FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	if "--geometry-only" in OS.get_cmdline_user_args():
		world.free();print("BOULDER_FRACTURE_GEOMETRY checks=",checks," failures=",failures);quit(1 if failures else 0);return
	var pose:=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*10),Vector3(0,1.17,0));var packed:=PackedFloat32Array()
	for row in 3:packed.append_array(PackedFloat32Array([pose.basis.x[row],pose.basis.y[row],pose.basis.z[row],pose.origin[row]]))
	check(fractures.upsert_rows(PackedInt64Array([100]),packed) and fractures.stage(100)==0,"unmined rock uses whole geometry")
	process_frame.connect(func():
		if is_instance_valid(fractures):fractures.advance(camera.global_position))
	await picture("whole")
	for stage in [1,2]:
		damage.hit("cover:100",240,80);fractures.sync_damage(100)
		check(fractures.stage(100)==stage,"saved damage selects fracture stage "+str(stage))
		await create_timer(.35).timeout;await picture("stage_"+str(stage))
	damage.hit("cover:100",240,80);fractures.sync_damage(100)
	check(fractures.stage(100)==2,"depleted but uncollected rock remains mineable")
	check(fractures.finish(100) and fractures.stage(100)==3,"successful final harvest produces eight pieces")
	if movie:
		await motion_clip()
		world.free();print("BOULDER_FRACTURE_MOTION checks=",checks," failures=",failures);quit(1 if failures else 0);return
	await create_timer(.05).timeout;await picture("stage_3_start")
	await create_timer(.15).timeout;await picture("stage_3_rolling")
	await create_timer(.25).timeout;await picture("stage_3_falling")
	await create_timer(.85).timeout;await picture("stage_3_landed")
	check(not fractures.finish(100),"finished rock cannot start a duplicate fracture")
	await create_timer(1.4).timeout
	check(fractures.stage(100)==-1 and fractures.statistics().roots==0,"terminal pieces retire after their bounded GPU animation")
	world.free();await process_frame
	print("BOULDER_FRACTURE_CACHE checks=",checks," failures=",failures);quit(1 if failures else 0)
