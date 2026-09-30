extends SceneTree
const Stream = preload("res://addons/volumetric_terrain/terrain_stream.gd")
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
class Fixed extends Stream:
	func _update_cut() -> void: pass
var world: Fixed
var checks: Array[Dictionary]=[]
var replies: Array[Dictionary]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks.append({"passed":ok,"name":label});print("PASS " if ok else "FAIL ",label)
func submit(token: int) -> bool:
	return world.request_density_ray(Vector3(1288,1.02,1288),Vector3(1288,0.98,1288),token)
func pump(predicate: Callable) -> void:
	var end := Time.get_ticks_msec()+5000
	while not predicate.call() and Time.get_ticks_msec()<end:
		for result: Dictionary in world.backend.poll(): world._receive(result)
		await process_frame
func hold_reply() -> Dictionary:
	var end := Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<end:
		for result: Dictionary in world.backend.poll():
			if result.kind=="density_ray": return result
			world._receive(result)
		await process_frame
	return {}
func run() -> void:
	world=Fixed.new();root.add_child(world);world.set_process(false)
	world.backend.disk_cache.enabled=false
	world.density_ray_received.connect(func(reply: Dictionary): replies.append(reply))
	check(not submit(0),"query rejected before world initialization")
	check(world.backend.start(true)==OK,"real backend starts")
	await pump(func(): return world.world_ready)
	check(world.world_ready and world.native_revision==0,"native revision captured at startup")
	check(submit(77),"current query admitted")
	var held := await hold_reply()
	check(not held.is_empty(),"real worker reply held before consumption")
	world._receive(held);world._receive(held)
	check(replies.size()==1 and replies[0].token==77 and replies[0].status=="hit","current reply delivered once with caller token")
	replies.clear();check(submit(88),"pre-edit query admitted")
	var old := await hold_reply()
	check(world.edit(Codec.brush(Vector3(1288,20,1288),Vector3(1288,20,1288),2,0,false,1),Vector3(1280,12,1280),Vector3(1296,28,1296)),"edit accepted while completed query is held")
	check(replies.size()==1 and replies[0].status=="stale" and not replies[0].has("position"),"accepted edit invalidates outstanding query")
	world._receive(old)
	check(replies.size()==1,"late pre-edit hit suppressed")
	check(not submit(89),"query blocked during pending publication")
	await pump(func(): return not world.pending_edit)
	check(not world.pending_edit and world.native_revision==1,"native revision advances after edit")
	replies.clear();check(submit(88),"caller token can be reused for a fresh request")
	world._receive(old)
	check(replies.is_empty(),"old serial cannot consume reused caller token")
	world._receive(await hold_reply())
	check(replies.size()==1 and replies[0].status=="hit" and replies[0].revision==1,"fresh revision hit delivered")
	replies.clear();check(submit(99),"pre-reload query admitted")
	held=await hold_reply();world.reload_world(true);world._receive(held)
	check(replies.size()==1 and replies[0].status=="stale" and not replies[0].has("position"),"reload suppresses old-world hit")
	await pump(func(): return world.world_ready)
	check(world.world_ready and world.native_revision==0,"reset publishes new world revision")
	replies.clear();check(submit(100),"revision guard query admitted")
	held=await hold_reply();held.revision=999;world._receive(held)
	check(replies.size()==1 and replies[0].status=="stale" and not replies[0].has("position"),"mismatched reply revision strips hit")
	replies.clear();check(submit(101),"shutdown query admitted")
	held=await hold_reply();world.shutdown();world._receive(held)
	check(replies.size()==1 and replies[0].status=="cancelled" and not replies[0].has("position"),"shutdown completes outstanding query without late hit")
	world.free()
	var failures := 0
	for entry: Dictionary in checks:
		if not entry.passed: failures+=1
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/terrain_density_stream_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Stream consumption of real held worker replies across edit, reset and shutdown. No player arbitration, rendered-surface accuracy or loaded latency qualification."},"  "));file.close()
	quit(0 if failures==0 else 1)
