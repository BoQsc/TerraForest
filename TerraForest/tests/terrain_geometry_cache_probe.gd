# SPDX-License-Identifier: 0BSD
extends SceneTree
const Backend = preload("res://addons/volumetric_terrain/terrain_backend.gd")
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
var backend: RefCounted
var checks: Array[Dictionary] = []
var timings: Array[Dictionary] = []
var serial := 0
const KEY := Vector3i(1280,1280,64)
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks.append({"passed":ok,"name":label});print("PASS " if ok else "FAIL ",label)
func receive(kind: String) -> Dictionary:
	var until := Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<until:
		for row: Dictionary in backend.poll():
			if row.kind==kind: return row
		await process_frame
	check(false,"worker timeout "+kind)
	return {}
func start_world() -> void:
	backend=Backend.new()
	backend.save_path="res://probe_world.trw"
	backend.cache_path="res://probe_cache"
	check(backend.start(false)==OK,"real backend starts")
	var row: Dictionary=await receive("startup")
	check(not str(row.get("message", "ERROR")).begins_with("ERROR"),"world loads")
func mesh(label: String, target: Vector3i = KEY) -> Dictionary:
	serial+=1
	check(backend.submit({"kind":"mesh","key":target,"base":false,"stamp":serial,"epoch":1}),"mesh admitted "+label)
	var row: Dictionary=await receive("mesh")
	check(not row.is_empty() and not row.has("error") and not row.get("cancelled",false),"mesh completes "+label)
	timings.append({"name":label,"worker_ms":row.get("worker_ms",-1),"geometry_cached":row.get("geometry_cached",false)})
	return row
func edit(command: PackedByteArray) -> void:
	serial+=1
	check(backend.submit({"kind":"edit","command":command,"tiles":[],"ticket":serial,"epoch":1},true),"edit admitted")
	var row: Dictionary=await receive("edit_done")
	check(not row.is_empty(),"changing edit completes")
func same_surface(a: Dictionary,b: Dictionary) -> bool:
	if not a.has("arrays") or not b.has("arrays"): return false
	for channel: int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_COLOR,Mesh.ARRAY_INDEX]:
		if a.arrays[channel]!=b.arrays[channel]: return false
	if a.collision_pieces.size()!=b.collision_pieces.size(): return false
	for i in range(a.collision_pieces.size()):
		if a.collision_pieces[i].get_faces()!=b.collision_pieces[i].get_faces(): return false
	return true
func key() -> Dictionary: return backend.native.geometry_cache_key(KEY.x,KEY.y,KEY.z,2)
func run() -> void:
	await start_world()
	var original_key: Dictionary=key()
	check(not original_key.is_empty(),"native dependency key is available")
	var cold: Dictionary=await mesh("cold")
	var warm: Dictionary=await mesh("warm")
	check(not cold.get("geometry_cached",true) and warm.get("geometry_cached",false),"actual backend writes and reuses disk geometry")
	check(same_surface(cold,warm),"warm result matches fresh geometry, shading and collision recipes")
	# Deliberately obsolete but checksum-valid visibility must never be trusted.
	var cache_file: String=backend.disk_cache._name(KEY,original_key.key)
	var stored: PackedByteArray=FileAccess.get_file_as_bytes(cache_file)
	var packet: PackedByteArray=stored.slice(40)
	var vertices: int=packet.decode_u32(24)
	for i in range(vertices*2): packet.encode_float(36+vertices*24+i*4,0.123)
	var replaced:=PackedByteArray();replaced.resize(8)
	replaced.encode_u32(0,backend.disk_cache.MAGIC);replaced.encode_u32(4,packet.size())
	replaced.append_array(backend.disk_cache.digest(packet));replaced.append_array(packet)
	var cache_writer:=FileAccess.open(cache_file,FileAccess.WRITE)
	cache_writer.store_buffer(replaced);cache_writer.close()
	var relit: Dictionary=await mesh("obsolete_visibility")
	check(relit.get("geometry_cached",false) and same_surface(cold,relit),"checksum-valid stale visibility is replaced before returning cached geometry")
	await edit(Codec.command(3,[100,200,100,1]))
	var remote_key: Dictionary=key()
	check(remote_key==original_key,"remote block edit preserves key and dependency work")
	var remote: Dictionary=await mesh("remote_edit")
	check(remote.get("geometry_cached",false),"geometry reused despite global snapshot-cache invalidation")
	backend.disk_cache.enabled=false
	var fresh: Dictionary=await mesh("remote_fresh_oracle")
	backend.disk_cache.enabled=true
	check(same_surface(remote,fresh),"remote-edit cached result equals a current uncached build")
	var remote_density: PackedByteArray=Codec.command(2);remote_density.resize(44)
	for offset: int in [4,16]:
		remote_density.encode_float(offset,100);remote_density.encode_float(offset+4,10);remote_density.encode_float(offset+8,100)
	remote_density.encode_float(28,2.5);remote_density.encode_u32(32,0);remote_density.encode_u32(36,0);remote_density.encode_u32(40,1)
	await edit(remote_density)
	check(key()==original_key,"remote density allocation preserves local content identity and lookup count")
	# Neighbor just outside owned geometry must invalidate occluded block faces.
	await edit(Codec.command(3,[1279,200,1288,1]))
	check(key().key!=original_key.key,"neighbor block dependency changes key")
	var neighbor: Dictionary=await mesh("neighbor_edit")
	check(not neighbor.get("geometry_cached",true),"neighbor dependency rejects stale disk geometry")
	var before_local: String=key().key
	await edit(Codec.command(3,[1288,200,1288,2]))
	check(key().key!=before_local,"local block edit changes key")
	var local: Dictionary=await mesh("local_edit")
	check(not local.get("geometry_cached",true),"local edit rebuilds instead of returning old geometry")
	var local_key: Dictionary=key()
	check(backend.submit({"kind":"save"}),"save admitted")
	var saved: Dictionary=await receive("message")
	check(str(saved.get("message", "ERROR")).begins_with("World saved"),"canonical save published")
	backend.stop();backend=null
	await start_world()
	check(key()==local_key,"dependency identity survives real save and world restart")
	var restarted: Dictionary=await mesh("restart")
	check(restarted.get("geometry_cached",false),"restart reuses geometry across snapshot namespace changes")
	check(same_surface(local,restarted),"restart geometry and refreshed visibility match pre-save result")
	# A changed density page must affect the key even without a placed block.
	var before_density: String=key().key
	var command: PackedByteArray=Codec.command(2)
	command.resize(44)
	for offset: int in [4,16]:
		command.encode_float(offset,1290);command.encode_float(offset+4,100);command.encode_float(offset+8,1290)
	command.encode_float(28,2.5);command.encode_u32(32,0);command.encode_u32(36,0);command.encode_u32(40,1)
	await edit(command)
	check(key().key!=before_density,"density excavation invalidates local content")
	var density: Dictionary=await mesh("density_edit")
	check(not density.get("geometry_cached",true),"excavation cannot reuse pre-edit geometry")
	var density_warm: Dictionary=await mesh("density_warm")
	check(density_warm.get("geometry_cached",false) and same_surface(density,density_warm),"edited density mesh caches with current shading")
	check(backend.native.geometry_cache_key(-1,0,32,1).is_empty(),"invalid key input rejected")
	var near_key:=Vector3i(1280,1280,32)
	var near_cold: Dictionary=await mesh("near_cold",near_key)
	var near_warm: Dictionary=await mesh("near_warm",near_key)
	check(near_warm.get("geometry_cached",false) and not near_warm.get("collision_pieces",[]).is_empty() and same_surface(near_cold,near_warm),"near cache preserves nonempty collision recipes and full surface channels")
	backend.stop();backend=null
	var failures:=0
	for row: Dictionary in checks:
		if not row.passed: failures+=1
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/terrain_geometry_cache_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"timings":timings},"\t"));file.close()
	quit(1 if failures else 0)
