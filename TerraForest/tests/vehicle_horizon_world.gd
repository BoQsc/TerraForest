# SPDX-License-Identifier: 0BSD
extends SceneTree
class LoadingFixture extends "res://demo/world.gd":
	var vehicle_packet:=PackedByteArray()
	var injected:=false
	var withheld:=false
	func _additional_loading_ready()->bool:
		if not injected:
			injected=world_vehicle.restore_snapshot(vehicle_packet)
			if not injected:terrain.latest_error="Vehicle fixture restoration failed";return false
		var ready:=super._additional_loading_ready()
		withheld=withheld or loading_stage_text=="Preparing world vehicles"
		return ready
const SAVE:="user://worlds/recipe_generated_4644d8cfc8f97e43.trw"
var game:Node3D
var failures:=0
var output:="res://reports/vehicle_horizon_world"
var samples:Array=[]
var surface_token:=-1
var surface_points:=PackedVector3Array()
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func until(predicate:Callable)->bool:
	var deadline:=Time.get_ticks_msec()+150000
	while not predicate.call() and Time.get_ticks_msec()<deadline and game.terrain.latest_error.is_empty():game.app_focused=true;await process_frame
	return predicate.call()
func surface_ready(token:int,points:PackedVector3Array,_normals:PackedVector3Array,_epoch:int,_revision:int)->void:
	if token==surface_token:surface_points=points
func capture(label:String,point:Vector3,offset:Vector3)->void:
	game.camera.global_position=point+offset;game.camera.look_at(point)
	for frame in 30:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	samples.append({"view":label,"far":game.world_vehicle.activation.coverage_status(),"near":game.world_vehicle.activation.parked_status,"bodies":game.world_vehicle.activation.residents.size()})
func run()->void:
	var options:=PackedStringArray(["--world-slot=recipe_generated_4644d8cfc8f97e43","--snapshot-readonly","--temporary","--ground-cover","--vehicle-fleet","--no-zombies"])
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--view-output="):output=argument.trim_prefix("--view-output=")
		if argument.begins_with("--derived-cache="):options.append(argument)
	DirAccess.make_dir_recursive_absolute(output)
	var original:=FileAccess.get_sha256(SAVE)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(options,true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path=""
	root.add_child(game)
	check(await until(func():return not game.loading_active),"populated read-only world loads with vehicle coverage gate")
	if failures:await finish(original);return
	game.set_process(false);game.set_physics_process(false);game.player_view.set_process(false);game._clear_motion()
	var session:Node=game.world_vehicle;var activation:RefCounted=session.activation
	check(session.restore_snapshot(PackedByteArray()),"test fleet resets only in-memory state")
	var roads:Array=game.generated_region.describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator).get("roads",[])
	roads=roads.filter(func(road:Dictionary):return float(road.width)>=7.0)
	roads.sort_custom(func(first:Dictionary,second:Dictionary):return first.a.distance_squared_to(first.b)>second.a.distance_squared_to(second.b))
	check(not roads.is_empty(),"fixture has actual generated regional roads")
	if failures:await finish(original);return
	var road:Dictionary=roads[0]
	var direction:Vector3=(road.b-road.a).normalized();var point:Vector3=road.a+direction*8+Vector3.UP*.85
	var identities:=PackedInt64Array()
	var probes:=PackedVector3Array()
	for index in 4:probes.append(point+direction*index*8)
	surface_token=preload("res://addons/volumetric_terrain/surface_tokens.gd").allocate()
	game.terrain.surface_batch_ready.connect(surface_ready)
	check(game.terrain.request_surface_batch(probes,surface_token) and await until(func():return surface_points.size()==4),"test vehicle poses use actual terrain samples, not interpolated road endpoint heights")
	game.terrain.surface_batch_ready.disconnect(surface_ready)
	if failures:await finish(original);return
	point=surface_points[0]+Vector3.UP*.85
	for position:Vector3 in surface_points:identities.append(session.fleet.spawn(Transform3D(Basis.IDENTITY,position+Vector3.UP*.85)))
	var saved:PackedByteArray=session.fleet.capture_storage_snapshot()
	game.terrain.focus=Vector3(1900,80,1900)
	check(await until(func():return activation.prepare_from_saved(game) and activation.coverage_status().ready),"never-near vehicle kind prepares across the full saved world")
	check(activation.coverage_status().rendered==4 and activation.residents.is_empty(),"all distant cars draw without activating driving bodies")
	check(activation.parked_view.horizon_statistics().parts==1,"production distant Ranger uses the verified offline consolidated prototype")
	var meshes:=0;var lods:=0
	for body:RigidBody3D in activation.bodies:
		for node:MeshInstance3D in body.find_children("*","MeshInstance3D",true,false):
			if node.mesh==null:continue
			meshes+=1
			for surface in node.mesh.get_surface_count():
				var data:Dictionary=RenderingServer.mesh_get_surface(node.mesh.get_rid(),surface)
				lods+=data.get("lods",[]).size()
	check(meshes==32 and lods>0,"actual Ranger retains existing imported geometry LODs rather than a proxy box")
	await capture("far_owned_near_view",point,Vector3(18,10,24))
	activation.refresh_parked(game)
	check(activation.parked_status.rendered==0 and activation.coverage_status().rendered==4,"remote physics focus does not retire distant vehicles")
	game.terrain.focus=point;activation.refresh_parked(game)
	check(activation.parked_status.rendered==4 and activation.coverage_status().rendered==0,"near promotion replaces exact far visuals without double rendering")
	await capture("near_owned",point,Vector3(18,10,24))
	game.terrain.focus=Vector3(1900,80,1900);activation.refresh_parked(game)
	check(activation.coverage_status().rendered==4 and activation.parked_status.rendered==0,"leaving 128 m restores every far car immediately")
	await capture("far_owned_distant_view",point,Vector3(0,180,350))
	check(session.fleet.capture_storage_snapshot()==saved,"render and near/far handoffs never alter canonical fleet bytes")
	check(session.restore_snapshot(saved),"vehicle component snapshot restores")
	check(await until(func():return activation.prepare_from_saved(game) and activation.coverage_status().ready) and activation.coverage_status().rendered==4,"restored component reconstructs full vehicle coverage")
	session.fleet.remove(identities[0])
	check(await until(func():return activation.coverage_status().ready) and activation.coverage_status().rendered==3,"far despawn removes its visual without a local visit")
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED,"offscreen test never captures the OS mouse")
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	preload("res://addons/world_runtime/session_options.gd").set_arguments(options,true)
	var restored:=LoadingFixture.new();restored.vehicle_packet=saved;restored.temporary_world=true;restored.background_fps=60;restored.player_view.settings_path=""
	game=restored;root.add_child(game)
	check(await until(func():return not game.loading_active) and restored.injected and restored.withheld,"production loading gate withholds play until restored vehicle visuals are ready")
	var state:Dictionary=restored.world_vehicle.activation.coverage_status()
	var near:int=restored.world_vehicle.activation.parked_status.get("rendered",0)
	check(state.ready and state.rendered+near+restored.world_vehicle.activation.residents.size()==4,"restored vehicles have exactly one representation when play is allowed")
	samples.append({"view":"restored_loading_gate","far":state,"near":near,"withheld":restored.withheld})
	await finish(original)
func finish(original:String)->void:
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	check(FileAccess.get_sha256(SAVE)==original,"populated source save remains unchanged")
	var file:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"samples":samples,"scope":"Populated read-only world with an in-memory four-Ranger fleet; component binary restored into a second world before its production play gate. Not a persisted compound-save or physical driving endurance test."},"  "));file.close()
	print("VEHICLE_HORIZON_WORLD failures=",failures)
	quit(1 if failures else 0)
