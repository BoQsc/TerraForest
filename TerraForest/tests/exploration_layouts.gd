# SPDX-License-Identifier: 0BSD
extends SceneTree
const Layouts=preload("res://addons/exploration/cave_layouts.gd")
const Earthworks=preload("res://addons/world_runtime/generation_earthworks.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var checks:=0
var failures:=0
var core:RefCounted
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func density(point:Vector3)->float:
	var cell:=point.floor();var fraction:=point-cell;var result:=0.0
	for corner in 8:
		var offset:=Vector3(corner&1,(corner>>1)&1,(corner>>2)&1)
		var weight:float=(fraction.x if offset.x else 1-fraction.x)*(fraction.y if offset.y else 1-fraction.y)*(fraction.z if offset.z else 1-fraction.z)
		if weight>0:result+=lattice(cell+offset)*weight
	return result
func lattice(point:Vector3)->float:
	var bytes:=Codec.command(7);bytes.resize(16)
	bytes.encode_float(4,point.x);bytes.encode_float(8,point.y);bytes.encode_float(12,point.z)
	return core.execute(bytes).decode_float(16)
func run()->void:
	if not ClassDB.class_exists("TerrainCore"):GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	core=ClassDB.instantiate("TerrainCore")
	var layouts:=Layouts.load_catalog()
	check(layouts.size()==2,"both original bounded location layouts load")
	if layouts.size()!=2:quit(1);return
	var origin:=Vector3i(100,40,100)
	var invalid:=Layouts.segments(layouts[0],origin,0)
	for mutation:Dictionary in [{"phase":""},{"cut_only":false},{"rectangular":true},{"level_caps":true},{"shoulder":1.0},{"coefficients":PackedFloat32Array()}]:
		var bad_segments:=invalid.duplicate(true);bad_segments[0].merge(mutation,true)
		check(Earthworks.packets(bad_segments).is_empty(),"invalid arched generation profile rejects before baking: "+str(mutation.keys()[0]))
	for layout:Dictionary in layouts:
		for rotation in 4:
			core.execute(Codec.command(6,[1703,5]));core.execute(Codec.brush(Vector3(100,50,112),Vector3(100,50,112),40,1,true,1))
			var good:=true;var began:=Time.get_ticks_usec()
			for packet:PackedByteArray in Earthworks.packets(Layouts.segments(layout,origin,rotation)):
				if not Codec.reply_ok(core.execute(packet)):good=false
			check(good,"native excavation "+layout.id+" rotation "+str(rotation))
			var clear:=true
			for passage:Dictionary in layout.tunnels:
				var steps:=ceili(passage.start.distance_to(passage.finish)*2)
				for step in steps+1:
					var point:=Vector3(origin)+Layouts.turn(passage.start.lerp(passage.finish,float(step)/steps),rotation)
					for offset in [Vector3(0,.75,0),Vector3(0,1.8,0),Vector3(.35,1,0),Vector3(-.35,1,0),Vector3(0,1,.35),Vector3(0,1,-.35)]:
						if density(point+offset)<=0:clear=false
					if density(point-Vector3(0,.25,0))>=0:clear=false
			check(clear,"continuous supported 1.8 m routes through all rooms/branches")
			clear=true
			for sleeper:Array in layout.sleepers:
				var position:=Vector3(origin)+Layouts.turn(Layouts.point(sleeper),rotation)
				for offset in [Vector3(0,1.8,0),Vector3(.9,.5,0),Vector3(-.9,.5,0),Vector3(0,.5,1),Vector3(0,.5,-1)]:
					if density(position+offset)<=0:clear=false
			check(clear,"sleeper resting/waking envelopes have terrain clearance")
			clear=true
			for view:Array in layout.views.slice(1):
				if density(Vector3(origin)+Layouts.turn(Layouts.point(view),rotation))<=.15:clear=false
			check(clear,"authored interior camera anchors remain in air")
			clear=true
			for crate:Array in layout.crates:
				var position:=Vector3(origin)+Layouts.turn(Layouts.point(crate),rotation)
				for horizontal in [-.7,.7]:
					for depth in [-.7,.7]:
						for height in [.1,.85]:
							if density(position+Vector3(horizontal,height,depth))<=0:clear=false
				if density(position-Vector3(0,.25,0))>=0:clear=false
			check(clear,"supply-container footprints have support and clearance")
			var snapshot:PackedByteArray=core.execute(Codec.command(4));var restore:=Codec.command(5);restore.append_array(snapshot.slice(12))
			check(Codec.reply_ok(core.execute(restore)) and core.execute(Codec.command(4))==snapshot,"entire authored excavation saves and restores exactly")
			print("LAYOUT_COST ",layout.id," turn=",rotation," ms=",(Time.get_ticks_usec()-began)/1000.0," snapshot_bytes=",snapshot.size())
	core.execute(Codec.command(6,[1703,29]))
	var before:PackedByteArray=core.execute(Codec.command(4))
	var planned:Dictionary=core.plan_exploration_sites(layouts,[],[])
	print("EXPLORATION_PLAN ",planned)
	check(planned.get("ok",false) and planned.get("sites",[]).size()==2,"native search finds roof-covered natural hillsides for both layouts")
	check(core.execute(Codec.command(4))==before,"site search is read-only")
	if planned.get("ok",false):
		var repeated:Dictionary=core.plan_exploration_sites(layouts,[],[])
		check(repeated.get("sites")==planned.sites,"same seed/layout yields deterministic placements")
		for site:Dictionary in planned.sites:
			var layout:Dictionary=layouts.filter(func(value:Dictionary):return value.id==site.id)[0]
			var segments:=Layouts.segments(layout,site.origin,site.rotation);segments.push_front(site.approach)
			var good:=true
			for packet:PackedByteArray in Earthworks.packets(segments):
				if not Codec.reply_ok(core.execute(packet)):good=false
			check(good,"actual hillside earthworks succeed: "+site.id)
	var bad:=layouts.duplicate(true);bad[0].tunnels[0].half_width=NAN
	var unchanged:PackedByteArray=core.execute(Codec.command(4))
	check(not core.plan_exploration_sites(bad,[],[]).get("ok",true) and core.execute(Codec.command(4))==unchanged,"invalid mod geometry rejects before survey/mutation")
	var excluded:Dictionary=core.plan_exploration_sites(layouts,[Rect2(0,0,2000,2000)],[])
	check(excluded.get("ok",false) and excluded.sites.is_empty() and excluded.skipped.size()==2 and core.execute(Codec.command(4))==unchanged,"fully reserved world skips locations instead of overriding reservations")
	for seed_value in [1,42,321,99991]:
		core.execute(Codec.command(6,[seed_value,29]))
		var sampled:Dictionary=core.plan_exploration_sites(layouts,[],[])
		print("EXPLORATION_SEED ",seed_value," sites=",sampled.get("sites",[]).size()," ms=",sampled.get("worker_ms",-1))
		check(sampled.get("ok",false) and sampled.candidates<=32768 and sampled.sites.size()+sampled.skipped.size()==2,"bounded seeded search returns explicit placements or skipped layouts")
	print("EXPLORATION_LAYOUTS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
