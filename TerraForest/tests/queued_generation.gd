extends SceneTree

const Options=preload("res://addons/world_runtime/session_options.gd")
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
class DataGeneration extends "res://addons/world_runtime/generate_world_task.gd":
	func bake_photographs(_game:Node,_plan:Dictionary,_market:Dictionary,_connection:Dictionary)->bool:return true
	func bake_map_layers(_game:Node)->bool:return true
	func generate_prefab(game:Node,lot:Dictionary)->bool:
		var placed:bool=await super.generate_prefab(game,lot)
		if placed:return true
		var probes:Array=[]
		for offset in range(0,lot.asset.clearance_sample_count(),512):
			var points:PackedVector3Array=lot.asset.clearance_samples(lot.origin,lot.rotation,offset,512,int(lot.asset.get_meta("site_sample_band",0)))
			var query:=Codec.command(31,[game.terrain.density_revision,points.size()]);query.append_array(points.to_byte_array())
			var reply:PackedByteArray=game.terrain.backend.native.execute(query)
			if not Codec.reply_ok(reply):print("CLEARANCE_DIAGNOSTIC_QUERY ",reply);break
			for index in points.size():
				if reply.decode_float(20+index*4)<0 and probes.size()<16:probes.append({"point":points[index],"density":reply.decode_float(20+index*4)})
		print("CLEARANCE_DIAGNOSTIC ",{"origin":lot.origin,"rotation":lot.rotation,"band":lot.asset.get_meta("site_sample_band",0),"checked_target":game.foundation_check.checked_target,"checked_rotation":game.foundation_check.checked_rotation,"checked_asset":game.foundation_check.checked_asset==lot.asset,"probes":probes})
		return false

var checks:=0
var failures:=0
var completed:=false
var generation_code:=-1
var slot:="queued_generation_"+Crypto.new().generate_random_bytes(6).hex_encode()
var recipe:=Recipe.DEFAULTS.duplicate()
var generator:=23
var world_seed:=1703

func _initialize()->void:run.call_deferred()
func check(accepted:bool,label:String)->void:
	checks+=1
	if not accepted:failures+=1
	print("PASS " if accepted else "FAIL ",label)
func wait_for(predicate:Callable,seconds:int)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()

func run()->void:
	var restore_slot:=""
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--plan-seed="):world_seed=int(argument.get_slice("=",1))
		if argument.begins_with("--restore-generated="):restore_slot=argument.get_slice("=",1)
	if not restore_slot.is_empty():
		var pattern:=RegEx.new();pattern.compile("^queued_generation_[0-9a-f]{12}$")
		if pattern.search(restore_slot)==null:push_error("Invalid generated fixture slot");quit(2);return
		slot=restore_slot
	if "--frontier" in OS.get_cmdline_user_args():generator=preload("res://demo/world_launch.gd").terrain_generator(true,not "--natural-ground" in OS.get_cmdline_user_args())
	if "--city-generation" in OS.get_cmdline_user_args():
		recipe.biome=2;recipe.settlements=3;recipe.districts=3;recipe.network=2;recipe.trails=2;generator=22
	if "--distributed" in OS.get_cmdline_user_args():generator=25
	var output:="res://reports/queued_generation/"+slot+("_reopen" if not restore_slot.is_empty() else "")
	var ready:=false
	if restore_slot.is_empty():
		Options.set_arguments(PackedStringArray(["--world-slot="+slot,"--world-seed="+str(world_seed),"--world-generator="+str(generator),"--vehicle-fleet","--save-terrain-lots","--preparation-output="+output,"--world-recipe="+Marshalls.raw_to_base64(Recipe.encode(recipe))]),true)
		var task:=DataGeneration.new();task.root=root
		task.finished.connect(func(code:int):generation_code=code;completed=true)
		root.add_child(task)
		ready=await wait_for(func():return completed,180)
		check(ready and generation_code==0,"actual production planning, native baking, multi-door buildings and world save complete")
		if not ready or generation_code!=0:task.request_cancel();await wait_for(func():return completed,20);await finish();return
		task.free();await process_frame
	else:
		var exists:=FileAccess.file_exists("user://worlds/"+slot+".trw")
		check(exists,"fresh process receives the previously generated fixture")
		if not exists:await finish();return
	var path:="user://worlds/"+slot+".trw"
	var before:=FileAccess.get_sha256(path)
	check(not before.is_empty(),"new isolated world has a canonical saved root")
	Options.set_arguments(PackedStringArray(["--world-slot="+slot,"--world-seed="+str(world_seed),"--world-generator="+str(generator),"--vehicle-fleet","--snapshot-readonly"]),true)
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
	ready=await wait_for(func():return not game.loading_active or not game.terrain.latest_error.is_empty(),90)
	check(ready and game.terrain.latest_error.is_empty() and not game.loading_active,"generated world reopens through the actual game loader")
	if ready and game.terrain.latest_error.is_empty():
		game.set_physics_process(false);game._clear_motion()
		var deposits:Array=game.material_deposits.describe(world_seed,generator)
		check(not deposits.is_empty(),"generated mineral metadata restores")
		var planned:Dictionary=preload("res://addons/world_runtime/custom_world_plan.gd").build(world_seed,generator,recipe,output+"_plan")
		check(planned.get("ok",false) and planned.sites.size()==recipe.settlements*recipe.districts,"requested number of districts survives production generation and plan reconstruction")
		var identities:Dictionary={}
		for deposit:Dictionary in deposits:identities[deposit.id]=deposit.position
		var connected:=true
		check(planned.get("ok",false) and planned.get("material_deposits",[]).size()==deposits.size(),"persisted marker identities match the independently reconstructed generation plan")
		for deposit:Dictionary in planned.get("material_deposits",[]):
			connected=connected and identities.get(deposit.id,Vector3.INF)==deposit.position
			var center:Vector3=(deposit.start+deposit.finish)*.5
			for height in range(ceili(center.y),floori(deposit.position.y)):
				var query:=Codec.point_command(Vector3(deposit.position.x,height,deposit.position.z));query.encode_u32(0,26)
				var reply:PackedByteArray=game.terrain.backend.native.execute(query)
				connected=connected and Codec.reply_ok(reply) and reply.decode_u32(12)==deposit.material and reply.decode_float(16)<0
		check(connected,"every saved marker still has continuous mineable ore underneath after a real reopen")
		check(game.world_recipe.store.capture_snapshot()==Recipe.encode(recipe),"exact generation options restore from the saved world")
		check(not game.mouse_capture_requested,"generation and reopen never grant cursor capture")
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
	check(FileAccess.get_sha256(path)==before,"read-only verification leaves canonical world bytes unchanged")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("verification.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"slot":slot,"restored_existing":not restore_slot.is_empty(),"seed":world_seed,"generator":generator,"world_path":ProjectSettings.globalize_path(path),"world_sha256":before,"recipe":recipe,"scope":"production data generation and game reopen; photographs/map raster baking skipped in this fixture"},"  "))
	await finish()

func finish()->void:
	Options.reset()
	print("QUEUED_GENERATION checks=",checks," failures=",failures);quit(1 if failures else 0)
