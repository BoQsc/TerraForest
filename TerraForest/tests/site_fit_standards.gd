extends SceneTree

const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
const Works=preload("res://addons/world_runtime/generation_earthworks.gd")
var checks:=0
var failures:=0

func check(accepted:bool,label:String)->void:
	checks+=1
	if not accepted:failures+=1
	print("PASS " if accepted else "FAIL ",label)

func _initialize()->void:
	for seed_value in [0,42,1703,9999]:
		var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,23]))
		var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,16)
		var plan:Dictionary=Planner.locate(core,layout.sites[3].position)
		check(plan.get("ok",false),"complete terrain-fitting district / seed "+str(seed_value))
		if not plan.get("ok",false):continue
		var full_footprints:=true;var driveways:=true
		for lot:Dictionary in plan.lots:
			var bounds:AABB=lot.asset.placement_bounds(lot.origin,lot.rotation)
			var points:=PackedVector3Array()
			for row in range(ceili(bounds.size.z+2)+1):
				for column in range(ceili(bounds.size.x+2)+1):
					points.append(Vector3(bounds.position.x-1+minf(column,bounds.size.x+2),0,bounds.position.z-1+minf(row,bounds.size.z+2)))
			var heights:PackedFloat32Array=Planner.heights(core,points)
			full_footprints=full_footprints and heights.size()==points.size()
			for height in heights:full_footprints=full_footprints and lot.survey.grade-height<=2.001 and height-lot.survey.grade<=3.001
			if lot.asset.has_meta("garage_entrance"):
				var start:Vector3=lot.asset.get_meta("garage_entrance")
				for turn in lot.rotation:start=Vector3(1-start.z,start.y,start.x)
				start+=Vector3(lot.origin)
				var finish:Vector3=lot.entrance.segment.finish
				var across:=Vector3(-(finish-start).z,0,(finish-start).x).normalized()
				var probes:=PackedVector3Array()
				for index in range(ceili(start.distance_to(finish)*2)+1):
					var point:Vector3=start.lerp(finish,minf(index*.5/start.distance_to(finish),1))
					for side in [-2.5,0.0,2.5]:probes.append(point+across*side)
				var raw:PackedFloat32Array=Planner.heights(core,probes)
				for index in raw.size():driveways=driveways and probes[index].y-raw[index]<=2.001 and raw[index]-probes[index].y<=3.001
		check(full_footprints,"full footprint plus one-metre apron obeys cut/fill budgets, not only sparse supports")
		check(driveways,"complete five-metre garage access obeys the same terrain budgets")
		var works:Dictionary=Planner.earthworks(plan)
		var pads:=0
		for segment:Dictionary in works.segments:
			if segment.get("rectangular",false):pads+=1
		check(pads>=plan.lots.size(),"each lot has bounded rectangular preparation instead of rounded strip ends")
	var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,17]))
	var packet:=Codec.graded_bed(Vector3(500,70,500),Vector3(524,70,500),6,3,4,1)
	packet.resize(52);packet.encode_float(44,4);packet.encode_u32(48,1)
	check(Codec.reply_ok(core.execute(packet)),"native rectangular bed is accepted through the ordinary edit transaction")
	var corners:=true
	for point:Vector3 in [Vector3(500.25,69.5,494.25),Vector3(523.75,69.5,505.75)]:
		var query:=Codec.command(31,[core.execute(Codec.command(0)).decode_u32(12),2])
		query.append_array(PackedVector3Array([point,point+Vector3.UP]).to_byte_array())
		var reply:PackedByteArray=core.execute(query)
		corners=corners and Codec.reply_ok(reply) and reply.decode_float(20)<0 and reply.decode_float(24)>0
	check(corners,"rectangular bed keeps its corners at grade instead of capsule-shaped scoops")
	var before:PackedByteArray=core.execute(Codec.command(4));packet.encode_u32(48,2)
	check(not Codec.reply_ok(core.execute(packet)) and before==core.execute(Codec.command(4)),"unknown foundation profile cannot mutate terrain")
	print("SITE_FIT_STANDARDS checks=",checks," failures=",failures);quit(1 if failures else 0)
