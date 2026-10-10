# SPDX-License-Identifier: 0BSD
extends "res://tests/actor_population_cost.gd"
var overflow:=false
func sample_fleet(label: String,count: int) -> void:
	var activation=game.world_vehicle.activation
	while game.world_vehicle.fleet.statistics().records<count:
		var i: int=game.world_vehicle.fleet.statistics().records
		var position: Vector3=start+direction*(i%8)*6+side*(i/8)*5 if overflow else start+direction*i*6
		game.world_vehicle.fleet.spawn(Transform3D(Basis.IDENTITY,position))
	var admissions: Array=[]
	var deadline:=Time.get_ticks_msec()+12000
	while (activation.residents.size()<mini(count,4) or activation.parked_status.get("rendered",0)+activation.residents.size()!=count) and Time.get_ticks_msec()<deadline:
		await process_frame;activation.timer=0
		var begin:=Time.get_ticks_usec();activation.update(game,0.2)
		admissions.append((Time.get_ticks_usec()-begin)/1000.0)
	check(activation.residents.size()==mini(count,4) and activation.parked_status.get("rendered",0)+activation.residents.size()==count,label+" all records represented within four-body cap")
	var worst:=0.0
	for cost: float in admissions:worst=maxf(worst,cost)
	check(worst<=4,label+" activation call max<=4ms")
	for i in 30:await process_frame
	var rows: Array=[];var previous:=Time.get_ticks_usec()
	var viewport:=root.get_viewport_rid();RenderingServer.viewport_set_measure_render_time(viewport,true)
	for tick in 120:
		await process_frame
		var begin:=Time.get_ticks_usec();activation.update(game,1.0/60)
		var cost: float=(Time.get_ticks_usec()-begin)/1000.0
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec()
		rows.append({"frame_ms":(now-previous)/1000.0,"fleet_ms":cost,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(viewport),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"settled":settled(),"bodies":activation.bodies.size(),"represented":activation.residents.size()+activation.parked_status.get("rendered",0)});previous=now
	var result:={"phase":label,"admission_ms":admissions,"rows":rows,"summary":{}}
	for field in ["frame_ms","fleet_ms","gpu_ms","draw_calls","primitives"]:result.summary[field]=summary(rows,field)
	phases.append(result)
	check(rows.all(func(row):return row.bodies<=4 and row.represented==count),label+" representation and body bounds hold throughout")
	check(rows.all(func(row):return row.settled),label+" terrain and cover settled throughout measurement")
	check(result.summary.fleet_ms.p95<=1 and result.summary.fleet_ms.max<=2,label+" steady fleet p95<=1ms max<=2ms")
	check(result.summary.frame_ms.p95<=18.5,label+" frame p95<=18.5ms")
	print(label," ",JSON.stringify(result.summary)," admission_max_ms=",worst)
func run() -> void:
	overflow="--parked-overflow" in OS.get_cmdline_user_args()
	game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	game.terrain.backend.disable_snapshot_writes();game.set_process(false);game.set_physics_process(false);game._clear_motion()
	if not game.world_vehicle.fleet_enabled:game.terrain.shutdown();game.free();quit(2);return
	game.world_vehicle.restore_snapshot(PackedByteArray())
	var ends: PackedVector3Array=game.road_palette.prepared_streets[0].ends
	direction=(ends[1]-ends[0]).normalized();side=Vector3(-direction.z,0,direction.x);start=ends[0]+direction*3+Vector3.UP*0.85
	game.terrain.focus=start;game.player.position=start+Vector3(0,3,8)
	game.camera.global_position=start-direction*12+Vector3.UP*8;game.camera.look_at(start+direction*10)
	var idle:=0;deadline=Time.get_ticks_msec()+30000
	while idle<60 and Time.get_ticks_msec()<deadline:await process_frame;idle=idle+1 if settled() else 0
	check(idle==60,"world settles before fleet cost comparison")
	await sample_fleet("empty",0);await sample_fleet("parked1",1);await sample_fleet("parked4",4)
	if overflow:
		await sample_fleet("parked16",16);await sample_fleet("parked64",64)
	var folder:="res://reports/vehicle_parked_cost" if overflow else "res://reports/vehicle_fleet_cost"
	DirAccess.make_dir_recursive_absolute(folder)
	var file:=FileAccess.open(folder+"/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"phases":phases},"  "));file.close()
	root.get_texture().get_image().save_png(folder+"/world.png")
	game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)
