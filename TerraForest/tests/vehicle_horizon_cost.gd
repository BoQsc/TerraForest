# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var output:="res://reports/vehicle_horizon_cost"
var camera:Camera3D
var view:Node3D
var fleet:RefCounted
var samples:Array=[]
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func summarize(values:Array)->Dictionary:
	values.sort()
	return {"median":values[values.size()/2],"p95":values[int((values.size()-1)*.95)],"max":values.back()}
func measure(label:String,count:int,spread:bool,offset:Vector3)->void:
	check(fleet.restore_storage_snapshot(PackedByteArray()),label+" resets canonical test fleet")
	var width:=maxi(1,ceili(sqrt(count)))
	var spacing:=30.0 if spread else 6.0
	var middle:=Vector3(8+(width-1)*spacing*.5,1,8+(width-1)*spacing*.5)
	camera.position=middle+offset;camera.look_at(middle)
	var accepted:=true
	for index in count:
		accepted=accepted and fleet.spawn(Transform3D(Basis.IDENTITY,Vector3(8+index%width*spacing,1,8+index/width*spacing)))!=0
	check(accepted,label+" spawns all requested records")
	var started:=Time.get_ticks_usec();var admissions:Array=[]
	while not view.statistics().ready and Time.get_ticks_usec()-started<30000000:
		await process_frame
		admissions.append(view.statistics().last_us/1000.0)
	check(view.statistics().ready and view.statistics().rendered==count,label+" all records published")
	var initial:Dictionary=view.statistics()
	for frame in 60:await RenderingServer.frame_post_draw
	var viewport:=root.get_viewport_rid()
	var previous:=Time.get_ticks_usec();var rows:Array=[]
	for frame in 120:
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec()
		rows.append({"frame_ms":(now-previous)/1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(viewport),"draw_calls":RenderingServer.viewport_get_render_info(viewport,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),"primitives_raw":RenderingServer.viewport_get_render_info(viewport,RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE,RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)})
		previous=now
	var summary:Dictionary={}
	for field:String in ["frame_ms","gpu_ms","render_cpu_ms","draw_calls","primitives_raw"]:
		summary[field]=summarize(rows.map(func(row:Dictionary):return row[field]))
	check(view.statistics().upload_bytes==initial.upload_bytes,label+" idle transforms never upload")
	var result:Dictionary={"label":label,"count":count,"spread":spread,"camera_offset":offset,"admission_ms":admissions,"native":initial,"summary":summary,"rows":rows}
	samples.append(result)
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	print("FLEET_RENDER_COST ",label," ",JSON.stringify(summary))
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--view-output="):output=argument.trim_prefix("--view-output=")
	DirAccess.make_dir_recursive_absolute(output)
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	camera=Camera3D.new();camera.far=5000;root.add_child(camera);camera.current=true
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("566474")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.6
	root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-50,-25,0);root.add_child(sun)
	var body:RigidBody3D=load("res://vehicle_demo/scenes/car.tscn").instantiate();body.freeze=true;body.process_mode=Node.PROCESS_MODE_DISABLED
	root.add_child(body);body.set_controls_enabled(false);body.set_physics_process(false)
	await process_frame
	var parts:Array=[];var material_ids:Dictionary={};var mesh_surfaces:=0;var source_triangles:=0;var lod_levels:=0
	for node:MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
		if node.mesh==null or not node.is_visible_in_tree():continue
		parts.append({"mesh":node.mesh,"transform":body.global_transform.affine_inverse()*node.global_transform,"material":node.material_override})
		for surface in node.mesh.get_surface_count():
			var material:Material=node.get_active_material(surface)
			material_ids[material.get_instance_id() if material!=null else 0]=true
			mesh_surfaces+=1;source_triangles+=node.mesh.surface_get_array_index_len(surface)/3
			lod_levels+=RenderingServer.mesh_get_surface(node.mesh.get_rid(),surface).get("lods",[]).size()
	check(parts.size()==32 and lod_levels>0,"actual 32-part Ranger prototype retains imported LODs")
	body.free()
	fleet=ClassDB.instantiate("NativeVehicleFleet");view=ClassDB.instantiate("NativeVehicleHorizon");root.add_child(view)
	check(view.configure(fleet,parts,"terraforest.ranger.v1"),"actual vehicle render horizon configures")
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	await measure("empty",0,false,Vector3(0,20,35))
	await measure("dense64",64,false,Vector3(0,35,65))
	await measure("dense1024",1024,false,Vector3(0,180,300))
	await measure("dense1024_close",1024,false,Vector3(-93,3,-101))
	await measure("world4096",4096,true,Vector3(0,1800,1600))
	await measure("world4096_close",4096,true,Vector3(-945,3,-953))
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED,"offscreen measurement never captures the OS mouse")
	var report:Dictionary={"failures":failures,"prototype":{"parts":parts.size(),"materials":material_ids.size(),"surfaces":mesh_surfaces,"source_triangles":source_triangles,"imported_lod_levels":lod_levels},"samples":samples,"scope":"Isolated actual-Ranger GPU/render-cost baseline; no terrain, world physics, driving, shadow casting or visual acceptance. Functional assertions gate this check, not arbitrary performance thresholds. Frame samples include the 60 FPS cap; raw primitive counters are engine-dependent, not submitted per-instance triangle totals."}
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	view.free();camera.free();sun.free();environment.free();await process_frame
	print("VEHICLE_HORIZON_COST failures=",failures);quit(1 if failures else 0)
