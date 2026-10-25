extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var slot:=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--inspect-slot="):slot=argument.trim_prefix("--inspect-slot=")
	if not slot.is_valid_identifier():quit(2);return
	var path:="user://worlds/"+slot+".trw"
	var archive:RefCounted=ClassDB.instantiate("NativeWorldArchive")
	var decoded:Dictionary=archive.decode(FileAccess.get_file_as_bytes(path))
	if not decoded.get("ok",false):quit(2);return
	var pose_codec:RefCounted=ClassDB.instantiate("NativePlayerPose")
	var pose:Dictionary=pose_codec.decode(decoded.sections.player_pose)
	var region:RefCounted=ClassDB.instantiate("NativeGeneratedRegion")
	if not region.restore_snapshot(decoded.sections.generated_region):quit(2);return
	var plan:Dictionary=region.get_plan()
	var payload:PackedByteArray=preload("res://tests/terrain_storage_support.gd").expand(path,decoded.sections.terrain)
	var core:RefCounted=ClassDB.instantiate("TerrainCore")
	var command:=Codec.command(5);command.append_array(payload)
	if not Codec.reply_ok(core.execute(command)):quit(2);return
	var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
	var roads:Array=plan.roads
	for road:Dictionary in roads:
		road.distance=Geometry3D.get_closest_point_to_segment(pose.position,road.a,road.b).distance_to(pose.position)
	roads.sort_custom(func(first:Dictionary,second:Dictionary)->bool:return first.distance<second.distance)
	var report:={"slot":slot,"seed":plan.seed,"generator":plan.generator,"pose":pose,"places":plan.places,"roads":[],"scope":"Read-only density survey; no save mutation or generated-terrain regeneration."}
	for road:Dictionary in roads.slice(0,12):
		var samples:Array=[]
		for step in 9:
			var point:Vector3=road.a.lerp(road.b,float(step)/8)
			var reply:=Codec.decode_density_ray(core.execute(Codec.density_ray_command(point+Vector3.UP*6,point-Vector3.UP*6,4096,epoch)))
			samples.append(reply)
		report.roads.append({"road":road,"samples":samples})
	DirAccess.make_dir_recursive_absolute("res://reports/road_grid_trial")
	FileAccess.open("res://reports/road_grid_trial/audit.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("ROAD_GRID_AUDIT ",slot," ",pose," nearest=",roads[0])
	quit(0)
