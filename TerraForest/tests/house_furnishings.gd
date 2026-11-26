# SPDX-License-Identifier: 0BSD
extends SceneTree
const Layout=preload("res://addons/structures/house_furnishings.gd")
const Homes=preload("res://addons/structures/furniture_catalog.gd")
const E2=preload("res://addons/structures/expansion_catalog.gd")
const City=preload("res://addons/structures/city_catalog.gd")
const Packs=preload("res://addons/structures/pack_registry.gd")
const Outdoors=preload("res://addons/structures/outdoor_generation.gd")
const Intro=preload("res://addons/world_runtime/introduction_spawn.gd")
var checks:=0
var failures:=0
var folder:=""
var world:Node3D
var cases:Array[Dictionary]=[]
var report:Dictionary={"houses":[]}
var restore_fixture:=""
var restore_hash:=""
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="):folder=arg.trim_prefix("--check-evidence-dir=")
		if arg.begins_with("--restore-fixture="):restore_fixture=arg.trim_prefix("--restore-fixture=")
		if arg.begins_with("--fixture-sha256="):restore_hash=arg.trim_prefix("--fixture-sha256=")
	run.call_deferred()
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
	return ok
func setup()->Node3D:
	var result:=preload("res://addons/structures/structures_world.gd").new();root.add_child(result)
	Packs.register(result)
	Homes.register(result)
	preload("res://addons/structures/storage_catalog.gd").register(result)
	preload("res://addons/structures/window_catalog.gd").register(result)
	preload("res://addons/structures/guardrail_catalog.gd").register(result)
	var doors:=preload("res://addons/structures/object_catalog.gd").new();doors.prepare();doors.register_all(result)
	return result
func run()->void:
	world=setup()
	if not restore_fixture.is_empty():
		var bytes:=FileAccess.get_file_as_bytes(restore_fixture)
		check(restore_hash.length()==64 and FileAccess.get_sha256(restore_fixture)==restore_hash,"fresh process reads the exact retained furnishing fixture")
		check(world.restore_storage_snapshot(bytes) and world.capture_storage_snapshot()==bytes,"fresh process restores every building, furniture transform and native object identity")
		world.free();await process_frame
		print("HOUSE_FURNISHINGS checks=",checks," failures=",failures);quit(1 if failures else 0);return
	for id:String in ["cottage_a2","house_c1","shop_b1","shop_b2","trader_t1"]:
		cases.append({"name":id,"asset":E2.asset(id),"source":load("res://addons/structures/prefabs/expansion_"+id+"_e2.tres")})
	cases.append({"name":"apartments_a3","asset":City.asset(5),"source":load("res://addons/structures/prefabs/city_apartments_a3.tres")})
	for floors in [2,3,4]:cases.append({"name":"tower_%d"%floors,"asset":Homes.furnished_tower(floors)})
	cases.append({"name":"workshop","asset":preload("res://addons/structures/workshop_catalog.gd").workshop()})
	cases.append({"name":"basic_cottage","asset":Homes.furnished_cottage(true,true)})
	cases.append({"name":"brick_cottage","asset":Layout.apply(load("res://addons/structures/prefabs/brick_cottage.tres"),"cottage_legacy")})
	var count:=0
	var lots:Array=[]
	for entry:Dictionary in cases:
		var asset:Resource=entry.asset
		if not check(asset!=null,"normal catalog constructs "+entry.name):continue
		var details:Array=asset.get_meta("homestead_layout",[])
		check(not details.is_empty(),"new pack furnishings in "+entry.name)
		if entry.has("source"):
			var source:Resource=entry.source;var original:Array=source.get_model_attachments()
			check(asset.get_records()==source.get_records() and asset.get_model_attachments().slice(0,original.size())==original,"building fabric and inherited objects preserved: "+entry.name)
			check(Layout.apply(asset,entry.name)==asset,"furnishing application is idempotent: "+entry.name)
		var origin:=Vector3i(count*70,30,0);entry.origin=origin
		lots.append({"asset":asset,"origin":Vector3i(100+count*70,30,100),"rotation":count%4})
		var placer:RefCounted=ClassDB.instantiate("NativePrefabPlacement")
		var result:Dictionary=placer.place(world.blocks,asset,origin,0,world.model_collections(),[])
		check(result.get("ok",false),"native collision/attachment transaction: "+entry.name+" / "+str(result.get("reason","ok")))
		var rotations:=true
		for turn in range(1,4):
			var rotated:Dictionary=placer.place(world.blocks,asset,origin+Vector3i(0,0,turn*60),turn,world.model_collections(),[])
			rotations=rotations and rotated.get("ok",false)
		check(rotations,"all four native building rotations preserve clear attachments: "+entry.name)
		if entry.name=="house_c1":
			var poses:Array[Transform3D]=[]
			for segment in range(1,Intro.EXIT.size()):
				var a:Vector3=Intro.EXIT[segment-1];var b:Vector3=Intro.EXIT[segment]
				var steps:=maxi(1,ceili(a.distance_to(b)*4))
				for step in steps+1:poses.append(Transform3D(Basis.IDENTITY,Vector3(origin)+a.lerp(b,float(step)/steps)))
			var clear:=true
			for key:String in world.model_collections():
				if key=="architecture/wooden_door/v1":continue
				var mask:PackedByteArray=world.model(key).overlap_mask(poses,AABB(Vector3(-.34,.04,-.34),Vector3(.68,1.76,.68)))
				clear=clear and mask.size()==poses.size() and mask.count(0)==mask.size()
			check(clear,"ordinary upstairs introduction exit remains clear of all furniture")
		var beds:=details.filter(func(row:Dictionary):return row.item==720).size()
		if entry.name=="cottage_a2" or entry.name=="house_c1":check(beds>=1,"house has a new sleeping area: "+entry.name)
		if entry.name=="apartments_a3":check(beds==16,"all sixteen apartment units receive beds")
		if entry.name.begins_with("tower_"):check(beds==int(entry.name.trim_prefix("tower_")),"every residential tower floor receives a bed")
		report.houses.append({"name":entry.name,"new_objects":details.size(),"total_objects":asset.get_model_attachments().size(),"placed":result.get("ok",false),"beds":beds})
		print("HOUSE_LAYOUT ",entry.name," objects=",details.size())
		count+=1
	var outdoor_count:=0;var choices:Dictionary={}
	for lot:Dictionary in lots:
		var a:=Outdoors.candidates(lot,1703);var b:=Outdoors.candidates(lot,1703)
		check(a.size()>=32 and a.size()<=Outdoors.ATTEMPTS,"many bounded outdoor proposals per building")
		check(a.map(func(row:Dictionary):return [row.item,row.pose])==b.map(func(row:Dictionary):return [row.item,row.pose]),"outdoor proposals repeat by world seed and lot")
		for candidate:Dictionary in a:choices[candidate.item]=true
		outdoor_count+=a.size()
	check(choices.size()==Outdoors.ITEMS.size(),"outdoor mix includes storage, tires, refuse, garden and household objects")
	var blocked:=Outdoors.candidates(lots[0],1703,[{"a":Vector3(0,0,100),"b":Vector3(2000,0,100),"width":100}])
	check(blocked.is_empty(),"road/approach reservations reject outdoor proposals")
	report.outdoor_proposals=outdoor_count
	var saved:PackedByteArray=world.capture_storage_snapshot()
	check(saved.size()<4*1024*1024,"bounded native furnishing fixture")
	var reopened:=setup()
	check(reopened.restore_storage_snapshot(saved) and reopened.capture_storage_snapshot()==saved,"fresh native owners restore every furnishing and unchanged building")
	reopened.free()
	if DisplayServer.get_name()!="headless" and failures==0:await pictures()
	report.checks=checks;report.failures=failures
	FileAccess.open(folder.path_join("house_furnishings.json"),FileAccess.WRITE).store_string(JSON.stringify(report))
	FileAccess.open(folder.path_join("furnishings.bin"),FileAccess.WRITE).store_buffer(saved)
	world.free();await process_frame
	print("HOUSE_FURNISHINGS checks=",checks," failures=",failures);quit(1 if failures else 0)
func pictures()->void:
	root.size=Vector2i(1280,720)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("a9c6cf");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("e5eff1");environment.environment.ambient_light_energy=.8;root.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-48,-25,0);sun.light_energy=1.5;sun.shadow_enabled=true;root.add_child(sun)
	var camera:=Camera3D.new();camera.fov=78;root.add_child(camera);camera.make_current()
	for view:Dictionary in [{"name":"cottage","case":0,"from":Vector3(.3,3.6,3.4),"to":Vector3(.0,2.8,-2.2)},{"name":"house","case":1,"from":Vector3(-1.4,6.6,-1),"to":Vector3(-2.8,5.8,-4.6)},{"name":"apartments","case":5,"from":Vector3(8.2,2.6,8.7),"to":Vector3(4.7,1.8,3.7)}]:
		var entry:Dictionary=cases[view.case];var origin:=Vector3(entry.origin)
		world.blocks.set_focus(origin+view.from);world.blocks.set_collision_radius(48);world.blocks.flush_bakes();world.set_model_focus(origin+view.from)
		camera.position=origin+view.from;camera.look_at(origin+view.to)
		for frame in 40:await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(folder.path_join(view.name+".png"))==OK,"captured actual furnished "+view.name+" interior")
	camera.free();sun.free();environment.free()
