# SPDX-License-Identifier: 0BSD
extends SceneTree
const Outdoors=preload("res://addons/structures/outdoor_generation.gd")
const Reference=preload("res://tests/fixtures/outdoor_generation_reference.gd")
var checks:=0
var failures:=0

class Terrain extends Node:
	signal density_batch_ready(result:Dictionary)
	signal surface_batch_ready(token:int,positions:PackedVector3Array,normals:PackedVector3Array,epoch:int,revision:int)
	var epoch:=3
	var density_revision:=7
	var published_revision:=7
	var changed_since_save:=false
	var backend=Backend.new()
	var stopping:=false
	var flat_world:=false
	var requests:Array[int]=[]
	var invalid_on:=0
	var changed_on:=0
	var replaced_on:=0
	func request_density_scan(points:PackedVector3Array,token:int,_depth:int,interpolated:bool)->bool:
		assert(interpolated)
		requests.append(points.size())
		var values:=PackedFloat32Array()
		for point in points:values.append(NAN if not flat_world and point.x>30 else point.y)
		var result:Dictionary={"token":token,"epoch":epoch,"revision":density_revision,"status":"ok","values":values}
		if requests.size()==invalid_on:result.values=PackedFloat32Array()
		_deliver.call_deferred(result)
		return true
	func request_surface_batch(points:PackedVector3Array,token:int)->bool:
		var positions:=PackedVector3Array();var normals:=PackedVector3Array()
		for point in points:positions.append(Vector3(point.x,0,point.z));normals.append(Vector3.UP)
		surface_batch_ready.emit.call_deferred(token,positions,normals,epoch,published_revision)
		return true
	func _deliver(result:Dictionary)->void:
		if requests.size()==changed_on:density_revision+=1
		if requests.size()==replaced_on:epoch+=1
		density_batch_ready.emit(result)
	func reset()->void:
		requests.clear();invalid_on=0;changed_on=0;replaced_on=0;stopping=false

class Backend extends RefCounted:
	var world_seed:=1703
class Trees extends RefCounted:
	func candidates(cell:Vector2i,_seed:int,_density:float,_regional:bool,_biome:int)->Dictionary:
		return {"points":PackedVector3Array([Vector3(cell.x*64+61,0,cell.y*64+5),Vector3(cell.x*64+9,0,cell.y*64+16)]),"ids":PackedInt64Array([1,2])}
class Harvest extends RefCounted:
	func contains(id:int)->bool:return id==1
class Ecosystem extends RefCounted:
	var harvest_state=Harvest.new()
	var density:=1.0
	var biome_profile:=1
	var scatter=Trees.new()
	func _scatter()->RefCounted:return scatter
class Water extends RefCounted:
	func depth_at(point:Vector3)->float:return .1 if point.z>675 else 0
class Lakes extends RefCounted:
	var water=Water.new()
class Fleet extends RefCounted:
	func query_near(point:Vector3,_radius:float,_maximum:int,_budget:int)->Dictionary:
		return {"ok":true,"complete":true,"ids":PackedInt64Array([1]) if point.x>760 else PackedInt64Array()}
class Vehicles extends RefCounted:
	var fleet=Fleet.new()
class Locations extends RefCounted:
	func get_locations()->Array:return [{"bounds":AABB(Vector3(695,-1,615),Vector3(6,5,6))}]
class Quests extends RefCounted:
	var store=Locations.new()
class Models extends Node3D:
	var prototype:=AABB(Vector3(-.25,0,-.25),Vector3(.5,1,.5))
	var records:Array[PackedFloat32Array]=[]
	var obstacle:=false
	func overlap_mask(_poses:Array[Transform3D],bounds:AABB)->PackedByteArray:
		if obstacle:return PackedByteArray([int(bounds.intersects(AABB(Vector3(700,-1,620),Vector3(6,5,6))))])
		for record in records:
			var basis:=Basis(Vector3(record[0],record[4],record[8]),Vector3(record[1],record[5],record[9]),Vector3(record[2],record[6],record[10]))
			if bounds.intersects(Transform3D(basis,Vector3(record[3],record[7],record[11]))*prototype):return PackedByteArray([1])
		return PackedByteArray([0])
	func insert_instance(packed:PackedFloat32Array,_protection:AABB)->int:
		records.append(packed);return records.size()
class Structures extends RefCounted:
	var blocks:Models
	var models:Dictionary={}
	func model_collections()->Dictionary:return models
class Game extends Node:
	var terrain:Terrain
	var structures=Structures.new()
	var ecosystem=Ecosystem.new()
	var lakes=Lakes.new()
	var world_vehicle=Vehicles.new()
	var quests=Quests.new()
	var _initial_generation_spawn:=Vector3(690,0,610)
	var shutdown_requested:=false

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	test_candidates()
	if "--metropolis-candidates" in OS.get_cmdline_user_args():await test_metropolis_candidates()
	await test_publication()
	var terrain:=Terrain.new();root.add_child(terrain)
	var bounds:Array[AABB]=[]
	# Mixed footprints cross request boundaries; supported, floating and nonfinite
	# candidates exercise indexing independently of the batching implementation.
	for index in 48:
		bounds.append(AABB(Vector3(index,0 if index%3 else 1,0),Vector3(1+index%5,1,1+index%4)))
	var serial:Array[bool]=[]
	for box in bounds:
		check(Outdoors.support_probes(box).to_byte_array()==Reference.support_probes(box).to_byte_array(),"native support probe bytes match reference")
		var samples:=await Reference._density(terrain,Reference.support_probes(box))
		var supported:=true
		for index in samples.size():
			if not is_finite(samples[index]) or (samples[index]<0)!=(index%2==0):supported=false
		serial.append(supported)
	var serial_requests:=terrain.requests.size()
	terrain.reset()
	var batch:Dictionary=await Outdoors._support(terrain,bounds)
	check(batch.ok and batch.supported==serial,"batched support matches 48 individual terrain queries exactly")
	check(serial.has(true) and serial.has(false),"comparison includes accepted and rejected support")
	check(terrain.requests.size()>1 and terrain.requests.size()<serial_requests,"multiple bounded requests replace individual-object waits")
	check(terrain.requests.all(func(size:int):return size>0 and size<=4096 and size%2==0),"every request respects the terrain sample limit and paired probes")
	check(batch.samples==terrain.requests.reduce(func(total:int,size:int):return total+size,0),"all support samples are accounted for")
	terrain.reset()
	var empty:Dictionary=await Outdoors._support(terrain,[])
	check(empty.ok and empty.supported.is_empty() and terrain.requests.is_empty(),"empty lot submits no terrain work")
	for mode in ["invalid_on","changed_on","replaced_on"]:
		terrain.reset();terrain.set(mode,2)
		var rejected:Dictionary=await Outdoors._support(terrain,bounds)
		check(not rejected.ok and terrain.requests.size()==2,"partial batch cannot publish after "+mode)
	terrain.reset();terrain.stopping=true
	check(not (await Outdoors._support(terrain,bounds)).ok and terrain.requests.is_empty(),"shutdown cancels support work without submitting another query")
	terrain.reset()
	check(not (await Outdoors._support(terrain,[AABB(Vector3.ZERO,Vector3(30,1,30))])).ok and terrain.requests.is_empty(),"oversized individual support footprint fails without an unfulfillable request")
	terrain.free();await process_frame
	print("OUTDOOR_SUPPORT_BATCHES checks=",checks," failures=",failures);quit(1 if failures else 0)

func test_candidates()->void:
	check(Outdoors.Packs.discover(),"production outdoor catalog loads")
	var homes=preload("res://addons/structures/furniture_catalog.gd")
	var asset:Resource=homes.enclosed_cottage()
	for rotation in 4:
		for seed_value in [0,42,1703,2147483647]:
			var lot:Dictionary={"asset":asset,"origin":Vector3i(700,48,620),"rotation":rotation}
			var roads:Array=[{"start":Vector3(690,48,590),"finish":Vector3(710,48,670),"half_width":2.5},{"a":Vector3(650,48,630),"b":Vector3(760,48,630),"width":3.75}]
			var reference:Array=Reference.candidates(lot,seed_value,roads)
			var candidate:Array=Outdoors.candidates(lot,seed_value,roads)
			if reference!=candidate and not reference.is_empty() and not candidate.is_empty():print("PROPOSAL_DIFFERENCE ",reference[0].pose," / ",candidate[0].pose," counts ",reference.size()," / ",candidate.size())
			check(reference==candidate,"native proposals preserve RNG, rotations and road decisions: %d/%d"%[rotation,seed_value])

func fixture()->Game:
	var game:=Game.new();root.add_child(game)
	game.terrain=Terrain.new();game.terrain.flat_world=true;game.add_child(game.terrain)
	game.structures.blocks=Models.new();game.structures.blocks.obstacle=true;game.add_child(game.structures.blocks)
	for item:int in Outdoors.ITEMS:
		var row:Dictionary=Outdoors.Packs.by_item[item]
		var mesh:Mesh=load(row.directory+"/models/"+row.id+".tres")
		var model:=Models.new();model.prototype=mesh.get_aabb()
		for part:AABB in mesh.get_meta("collision_boxes"):model.prototype=model.prototype.merge(part)
		game.add_child(model);game.structures.models[row.key]=model
	return game

func test_publication()->void:
	var asset:Resource=preload("res://addons/structures/furniture_catalog.gd").enclosed_cottage()
	var lots:Array=[]
	for turn in 4:lots.append({"asset":asset,"origin":Vector3i(700+turn*20,0,620+turn*16),"rotation":turn,"label":"Native parity lot %d"%turn})
	var roads:Array=[{"start":Vector3(660,0,625),"finish":Vector3(780,0,625),"half_width":2.5}]
	var before:=fixture();var started:=Time.get_ticks_usec()
	var reference:Dictionary=await Reference.publish(before,lots,roads,1703)
	var reference_us:=Time.get_ticks_usec()-started
	var after:=fixture();started=Time.get_ticks_usec()
	var candidate:Dictionary=await Outdoors.publish(after,lots,roads,1703)
	var candidate_us:=Time.get_ticks_usec()-started
	check(reference.ok and candidate.ok,"complete native and reference publication finish")
	if reference.ok and candidate.ok:
		check(reference.placements==candidate.placements and reference.skipped==candidate.skipped,"ordered insertions retain IDs, exact transform bytes, counts and skips")
		check(reference.placements.size()>0 and reference.skipped>0,"publication comparison exercises acceptance and rejection")
		check(reference.density_requests==candidate.density_requests and reference.density_samples==candidate.density_samples,"publication surveys exactly the same support points")
		for key:String in before.structures.models:check(before.structures.models[key].records==after.structures.models[key].records,"native persisted transforms equal reference: "+key)
		check(after.terrain.changed_since_save and after.terrain.surface_batch_ready.get_connections().is_empty() and after.terrain.density_batch_ready.get_connections().is_empty(),"publication releases callbacks and marks native world dirty")
		print("NATIVE_OUTDOOR_PARITY ",JSON.stringify({"reference_us":reference_us,"native_us":candidate_us,"placements":candidate.placements.size(),"skipped":candidate.skipped,"profile":candidate.profile}))
	before.free();after.free();await process_frame

func test_metropolis_candidates()->void:
	var plan:Dictionary=preload("res://addons/world_runtime/world_generation_plan.gd").build(1703,33,true,true,"user://generation_plans",preload("res://addons/world_runtime/world_recipe.gd").METROPOLIS)
	if not plan.get("ok",false):check(false,"metropolis comparison plan available");return
	var lots:Array=[];var roads:Array=[]
	for site:Dictionary in plan.sites:lots.append_array(site.lots);roads.append_array(site.roads)
	for lot:Dictionary in lots:
		if lot.has("entrance"):roads.append(lot.entrance.segment)
	for road:Dictionary in plan.navigation.roads:roads.append({"start":road.a,"finish":road.b,"half_width":float(road.width)*.5})
	var reference_us:=0;var native_us:=0;var proposals:=0
	for lot:Dictionary in lots:
		var started:=Time.get_ticks_usec();var reference:Array=Reference.candidates(lot,1703,roads);reference_us+=Time.get_ticks_usec()-started
		started=Time.get_ticks_usec();var candidate:Array=Outdoors.candidates(lot,1703,roads);native_us+=Time.get_ticks_usec()-started
		check(reference==candidate,"exact native metropolis proposals: "+str(lot.origin))
		proposals+=reference.size();await process_frame
	print("METROPOLIS_PROPOSAL_PARITY ",JSON.stringify({"lots":lots.size(),"proposals":proposals,"roads":roads.size(),"reference_us":reference_us,"native_us":native_us,"digest":plan.plan_digest}))
