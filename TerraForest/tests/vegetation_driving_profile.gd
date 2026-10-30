extends "res://tests/runtime_travel_profile.gd"

var cruise_kph:=100.0
var coverage:Array=[]
var path_distance:=0.0
var path_total:=0.0
var path_lengths:=PackedFloat32Array()
var road_finished:=false
var boulder_baseline:Dictionary={}

func boulder_identities()->Dictionary:
	var result:Dictionary={}
	for key:Vector2i in game.ground_cover.boulders.resident:
		var row:Dictionary=game.ground_cover.boulders.resident[key][0]
		for index in row.ids.size():result[row.ids[index]]=row.transforms.slice(index*12,(index+1)*12)
	return result

func _initialize()->void:
	walking_seconds=35.0;route_steps=512
	profile_notes="Controlled constant-speed road-camera sweep through production vegetation streaming, not physical driving or vehicle collision qualification. Disk residency is not a pixel-visible gap count."
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--drive-kph="):cruise_kph=clampf(float(argument.trim_prefix("--drive-kph=")),30,198)
	super._initialize()

func move(_pressed:bool)->void:
	pass

func sample(label:String,seconds:float)->void:
	if label=="settling":
		boulder_baseline=boulder_identities()
		game.fly=true;game.player.velocity=Vector3.ZERO
		route.remove_at(0)
		path_lengths.append(0)
		for index in range(1,route.size()):
			path_total+=route[index].distance_to(route[index-1]);path_lengths.append(path_total)
		game.player.position=route[0]+Vector3.UP*1.0
		if not await until(func():return game.ground_cover.resident.size()==game.ground_cover._wanted.size() and game.ground_cover._requests.is_empty(),100):
			push_error("Ground cover did not settle before speed sweep");await finish(false);return
	if label!="walking":
		await super.sample(label,seconds);return
	phase=label
	var began:=Time.get_ticks_usec()
	while path_distance<path_total and Time.get_ticks_usec()-began<int(seconds*1000000):
		path_distance=minf(path_total,(Time.get_ticks_usec()-began)/1000000.0*cruise_kph/3.6)
		while route_index<route.size()-1 and path_lengths[route_index]<path_distance:route_index+=1
		var offset:Vector3=route[route_index]-route[route_index-1]
		var fraction:float=(path_distance-path_lengths[route_index-1])/maxf(.001,offset.length())
		game.player.position=route[route_index-1].lerp(route[route_index],fraction)+Vector3.UP*1.0
		game.player.velocity=Vector3.ZERO;game.player.rotation.y=atan2(-offset.x,-offset.z)
		await process_frame
	road_finished=path_distance>=path_total
	phase="capture"
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("moving-end.png"))

func missing_owners(wanted:Dictionary,resident:Dictionary,cell_size:float,radius:float)->int:
	var missing:=0
	for cell:Vector2i in wanted:
		if resident.has(cell):continue
		var offset:=Vector2(maxf(maxf(cell.x*cell_size-game.camera.global_position.x,0),game.camera.global_position.x-(cell.x+1)*cell_size),maxf(maxf(cell.y*cell_size-game.camera.global_position.z,0),game.camera.global_position.z-(cell.y+1)*cell_size))
		if offset.length_squared()<=radius*radius:missing+=1
	return missing

func frame()->void:
	super.frame()
	if not rows.is_empty():rows[-1]["boulder_us"]=game.ground_cover.boulders.last_process_us
	if rows.size()%12==0:
		var cover=game.ground_cover
		rows[-1]["ground_exclusion_revision"]=cover._exclusion_revision
		rows[-1]["ground_dirty_owners"]=cover._dirty.size()
		var boulder:Dictionary=cover.boulders.coverage_status()
		if boulder_identities()!=boulder_baseline or boulder.render.roots!=boulder_baseline.size():push_error("Boulder coverage lost during travel")
		rows[-1]["boulders"]=boulder
		coverage.append({"frame":rows.size(),"phase":phase,"ground_wanted":cover._wanted.size(),"ground_resident":cover.resident.size(),"ground_missing_near":missing_owners(cover._wanted,cover.resident,32,64),"ground_missing_visible":missing_owners(cover._wanted,cover.resident,32,cover._view_range),"ground_requests":cover._requests.size(),"ground_job_layer":cover._scatter_job.get("layer",-1),"forest_missing_visible":missing_owners(game.ecosystem._wanted,game.ecosystem.resident,64,576),"forest_requests":game.ecosystem._requests.size()})

func finish(success:bool)->void:
	FileAccess.open(output.path_join("driving.json"),FileAccess.WRITE).store_string(JSON.stringify({"cruise_kph":cruise_kph,"road_finished":road_finished,"path_distance":path_distance,"path_total":path_total,"coverage":coverage,"scope":"Controlled road-camera speed sweep, not a vehicle physics/steering qualification. Full production vegetation and terrain streaming; no density reductions. Missing-owner counts are disk residency diagnostics, not pixel-visible gaps."},"  "))
	await super.finish(success)
