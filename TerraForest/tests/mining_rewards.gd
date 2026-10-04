# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var terrain: Node
var hud: Node
var rewards: RefCounted
var persistence: RefCounted
var checks:=0
var failures:=0
var saved:=false
var slot:="mining_rewards_%d"%OS.get_process_id()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func open_world() -> bool:
	terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new();terrain.save_slot=slot
	terrain.diagnostics_pause_streaming=true;terrain.backend.disk_cache.enabled=false;terrain.backend.world_generator=3
	root.add_child(terrain)
	hud=preload("res://addons/player_runtime/player_hud.gd").new();hud.gameplay_construction=true
	if not hud.prepare(): return false
	persistence=preload("res://addons/world_runtime/world_persistence.gd").new()
	if not persistence.register_component("player_loadout",hud.capture_snapshot,hud.restore_snapshot,hud.inventory,hud.default_loadout): return false
	if not persistence.register_component("pending_rewards",hud.reward_inbox.capture_storage_snapshot,hud.reward_inbox.restore_storage_snapshot,hud.reward_inbox,hud.reward_inbox.capture_storage_snapshot()): return false
	rewards=preload("res://addons/player_runtime/mining_rewards.gd").new()
	if not rewards.attach(terrain,hud) or persistence.attach(terrain)!=OK: return false
	terrain.message_changed.connect(func(message: String):
		if message.begins_with("World saved and verified"): saved=true)
	if terrain.start(StandardMaterial3D.new(),false)!=OK: return false
	var deadline:=Time.get_ticks_msec()+10000
	while not terrain.world_ready and Time.get_ticks_msec()<deadline: await process_frame
	return terrain.world_ready
func close_nodes() -> void:
	terrain.shutdown();terrain.free();hud.free();rewards=null;persistence=null
func dig(center: Vector3) -> bool:
	return terrain.edit(Codec.brush(center,center,2,0,false,3),center-Vector3.ONE*8,center+Vector3.ONE*8)
func wait_edit() -> void:
	var deadline:=Time.get_ticks_msec()+10000
	while terrain.pending_edit and Time.get_ticks_msec()<deadline: await process_frame
	check(not terrain.pending_edit and not rewards.failed,"worker edit settles with reward accounting")
func run() -> void:
	Engine.max_fps=60
	check(await open_world(),"gameplay mining and persistence initialize")
	if not terrain.world_ready: close_nodes();quit(1);return
	var center:=Vector3(800,30,1310)
	check(not terrain.edit(Codec.brush(center,center,2,0,true,1),center-Vector3.ONE*8,center+Vector3.ONE*8),"gameplay blocks free terrain creation before mutation")
	check(dig(center),"gameplay excavation accepted")
	await wait_edit()
	var pending: PackedInt64Array=hud.reward_inbox.get_pending()
	check(not pending.is_empty() and pending[0] in [201,202,203] and pending[1]>0,"actual excavation produces raw-resource pending rewards")
	var receipt: int=hud.reward_inbox.get_last_receipt()
	rewards.published(AABB(),terrain.published_revision)
	check(hud.reward_inbox.get_pending()==pending and hud.reward_inbox.get_last_receipt()==receipt,"duplicate publication cannot repeat the receipt")
	check(dig(center),"repeated brush admitted")
	await wait_edit()
	check(hud.reward_inbox.get_pending()==pending,"mining the same empty space awards nothing")
	check(hud.reward_inbox.claim(hud.inventory,PackedInt64Array([pending[0],2]),hud.inventory.snapshot().revision).ok,"mined resource can be claimed into inventory")
	var recipe: int=0 if pending[0]==201 else (2 if pending[0]==202 else 3)
	check(preload("res://addons/player_runtime/crafting.gd").craft(hud.inventory,recipe,1,hud.inventory.snapshot().revision).ok,"actual mined resources craft into building supplies")
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var blocks=ClassDB.instantiate("NativeBlockWorld")
	var construction=preload("res://addons/player_runtime/construction_inventory.gd").new();construction.gameplay=true
	var word: int=1 if recipe==0 else 97
	check(construction.place_block(blocks,hud.inventory,Vector3i(10,0,10),word) and blocks.get_cell(Vector3i(10,0,10))==word,"crafted supply participates in paid native block placement")
	blocks.free()
	var inventory_bytes: PackedByteArray=hud.capture_snapshot()
	var reward_bytes: PackedByteArray=hud.reward_inbox.capture_storage_snapshot()
	saved=false;terrain.save_world()
	var deadline:=Time.get_ticks_msec()+10000
	while not saved and Time.get_ticks_msec()<deadline: await process_frame
	check(saved,"mined and claimed state saves")
	close_nodes()
	check(await open_world(),"gameplay save opens in new worker")
	check(hud.capture_snapshot()==inventory_bytes and hud.reward_inbox.capture_storage_snapshot()==reward_bytes,"claimed resource and remaining receipt restore exactly")
	check(dig(center+Vector3(12,0,0)),"excavation admitted immediately before graceful close")
	check(await terrain.shutdown_after_edits(),"graceful close settles mining reward")
	reward_bytes=hud.reward_inbox.capture_storage_snapshot()
	var revision: int=terrain.density_revision
	close_nodes()
	check(await open_world() and hud.reward_inbox.capture_storage_snapshot()==reward_bytes,"graceful-close reward persists")
	check(dig(center+Vector3(24,0,0)),"excavation admitted immediately before direct teardown")
	close_nodes()
	check(await open_world() and terrain.density_revision==revision and hud.reward_inbox.capture_storage_snapshot()==reward_bytes,"direct pending teardown preserves previous consistent save")
	var full=ClassDB.instantiate("NativeRewardInbox");full.accept(PackedInt64Array([201,1000000000000]),999)
	hud.reward_inbox.restore_storage_snapshot(full.capture_storage_snapshot())
	check(not dig(center+Vector3(36,0,0)) and not terrain.pending_edit and terrain.density_revision==revision,"saturated inbox rejects mining before terrain mutation")
	hud.reward_inbox.restore_storage_snapshot(reward_bytes)
	close_nodes()
	for suffix in [".trw",".trw.bak",".trw.lock"]: DirAccess.remove_absolute("user://worlds/"+slot+suffix)
	print("MINING_REWARDS ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
