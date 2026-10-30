# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func drain(view:Node3D)->bool:
	for tick in 10000:
		view.advance(128,3)
		if view.statistics().ready:return true
	return false
func run()->void:
	GDExtensionManager.load_extension("res://addons/vehicle_runtime/vehicle_runtime.gdextension")
	var fleet:RefCounted=ClassDB.instantiate("NativeVehicleFleet")
	var view:Node3D=ClassDB.instantiate("NativeVehicleHorizon");root.add_child(view)
	var mesh:=BoxMesh.new();var material:=StandardMaterial3D.new();material.albedo_color=Color.BLUE
	var local:=Transform3D(Basis.from_euler(Vector3(.1,.2,.3)).scaled(Vector3(2,3,4)),Vector3(1,2,3))
	check(not view.configure(fleet,[{}],"terraforest.ranger.v1"),"invalid prototype rejects atomically")
	check(view.configure(fleet,[{"mesh":mesh,"material":material,"transform":local}],"terraforest.ranger.v1"),"world renderer configures shared exact prototype")
	var identities:=PackedInt64Array()
	for index in 4096:
		identities.append(fleet.spawn(Transform3D(Basis.from_euler(Vector3(0,index*.1,0)),Vector3(8+(index%64)*30,20,(index/64)*30+8))))
	check(fleet.first_of_kind("terraforest.ranger.v1")==identities[0] and fleet.first_of_kind("absent")==0,"kind index locates never-near saved vehicles")
	view.advance(128,3)
	check(view.statistics().last_records<=128 and view.statistics().last_uploads<=3 and not view.statistics().ready,"initial world publication is bounded")
	check(drain(view) and view.represented_ids()==identities,"all 4096 records represented without a distance query")
	var stats:Dictionary=view.statistics()
	check(stats.pages<=96 and stats.instance_capacity_bytes<=96*128*48,"spatial pages stay compact and bounded")
	var first:MultiMeshInstance3D=view.get_child(0)
	var rendered:Transform3D=first.multimesh.get_instance_transform(0)
	check(rendered.is_equal_approx(fleet.get_record(identities[0]).pose*local) and first.material_override==material,"source transforms and material remain exact")
	check(first.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"distant batches do not extend physics or shadow work")
	var before:int=stats.upload_bytes;view.advance()
	check(view.statistics().upload_bytes==before and view.statistics().last_records==0,"idle view has no fleet scan or transform upload")
	fleet.set_module_state(identities[0],PackedByteArray([1,2,3]));view.advance()
	check(view.statistics().upload_bytes==before,"opaque vehicle state does not rebuild unchanged render poses")
	check(not view.set_excluded(PackedInt64Array([-1])) and view.represented_ids()==identities,"invalid handoff rejects without changing representation")
	check(view.set_excluded(PackedInt64Array([identities[0],identities[1000]])) and not view.represented_ids().has(identities[0]) and view.statistics().rendered==4094,"near/full-body handoff removes duplicate far geometry immediately")
	check(view.set_excluded(PackedInt64Array()) and view.represented_ids()==identities,"near retirement restores far representation in the same handoff")
	for index in 512:fleet.remove(identities[index])
	for index in range(512,1024):fleet.set_pose(identities[index],Transform3D(Basis.IDENTITY,Vector3(1800+index%64,100,1800)))
	view.advance(1,3)
	check(view.statistics().last_records==1,"queued deletion cannot dereference removed authoritative records")
	var continuous:=true
	for tick in 10000:
		view.advance(128,3)
		var visible:PackedInt64Array=view.represented_ids()
		for index in range(1,visible.size()):continuous=continuous and visible[index]!=visible[index-1]
		for identity:int in identities.slice(512):continuous=continuous and visible.has(identity)
		continuous=continuous and view.statistics().last_uploads<=3
		if view.statistics().ready:break
	check(continuous and view.statistics().ready and view.represented_ids()==identities.slice(512),"bounded cross-cell transactions never lose or duplicate unchanged vehicles")
	check(view.statistics().pages<=92,"moving records compact donor pages rather than accumulating holes")
	var snapshot:PackedByteArray=fleet.capture_storage_snapshot()
	var unknown:int=fleet.spawn_module(Transform3D(Basis.IDENTITY,Vector3(1500,20,1500)),"test.other")
	check(drain(view) and not view.represented_ids().has(unknown),"other vehicle kinds never receive substitute visuals")
	check(fleet.restore_storage_snapshot(snapshot) and view.statistics().rendered==0 and drain(view) and view.represented_ids()==identities.slice(512),"snapshot restoration rebuilds derived coverage and kind index")
	var restored:int=fleet.first_of_kind("terraforest.ranger.v1")
	check(restored==identities[512] and fleet.first_of_kind("test.other")==0,"kind index resets atomically with canonical snapshot")
	check(fleet.restore_storage_snapshot(PackedByteArray()),"capacity fixture starts from an empty canonical fleet")
	var cell_counts:Dictionary={}
	for index in 65536:
		var at:=Vector3(8+index%64*30,20+index/4096*3,8+(index/64)%64*30)
		fleet.spawn(Transform3D(Basis.IDENTITY,at))
		var cell:=Vector2i(floori(at.x/256),floori(at.z/256));cell_counts[cell]=int(cell_counts.get(cell,0))+1
	var expected_pages:=0
	for count:int in cell_counts.values():expected_pages+=ceili(count/128.0)
	var maximum_us:=0;var pressure_ready:=false
	for tick in 4096:
		view.advance(128,3)
		var pressure:Dictionary=view.statistics();maximum_us=maxi(maximum_us,pressure.last_us)
		if pressure.ready:pressure_ready=true;break
	check(pressure_ready and view.statistics().rendered==65536,"entire supported fleet capacity has distant representation")
	check(view.statistics().pages==expected_pages and view.statistics().instance_capacity_bytes==expected_pages*128*48,"capacity pressure retains exactly packed spatial pages without per-vehicle nodes")
	print("HORIZON_PRESSURE ",JSON.stringify({"max_step_us":maximum_us,"state":view.statistics()}))
	view.free()
	check(fleet.get_signal_connection_list("presentation_changed").is_empty() and fleet.get_signal_connection_list("presentation_reset").is_empty(),"renderer teardown releases fleet observers")
	var folder:="res://reports"
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--view-output="):folder=argument.trim_prefix("--view-output=")
	DirAccess.make_dir_recursive_absolute(folder)
	var report:=FileAccess.open(folder.path_join("vehicle_horizon.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"maximum_native_step_us":maximum_us,"scope":"Rendered buffer API and native ownership/pressure tests; one box prototype, not full-car GPU endurance."},"  "));report.close()
	print("VEHICLE_HORIZON checks=",checks," failures=",failures)
	quit(1 if failures else 0)
