# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const DIR="res://reports/geology_gameplay/"
var failures:=0
var rows: Array=[]
func check(ok: bool,label: String) -> void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void:run.call_deferred()
func pending(hud: Node) -> Dictionary:
	var out: Dictionary={};var raw: PackedInt64Array=hud.reward_inbox.get_pending()
	for i in range(0,raw.size(),2):out[int(raw[i])]=int(raw[i+1])
	return out
func run() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var reopen: bool="--reopen-geology" in OS.get_cmdline_user_args()
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var probe: RefCounted=ClassDB.instantiate("TerrainCore");probe.execute(Codec.command(6,[1703,4]))
	var found: Dictionary={}
	for x in range(320,448,4):
		for z in range(320,448,4):
			for y in range(8,56,4):
				var p:=Vector3(x,y,z);var packet:=Codec.point_command(p);packet.encode_u32(0,26)
				var reply: PackedByteArray=probe.execute(packet);var material:=reply.decode_u32(12)
				if material in [8,9] and reply.decode_float(16)<0 and absf(reply.decode_float(20))>0.9:found[material]=p
				if found.size()==2:break
			if found.size()==2:break
		if found.size()==2:break
	check(found.size()==2,"generator four contains solid iron and copper veins")
	if found.size()!=2:quit(1);return
	probe=null
	var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active and game.construction_inventory.gameplay,"actual world ready in gameplay mode")
	game.set_physics_process(false);game._clear_motion();game.fly=true;game.needs_floor_spawn=false
	if reopen:
		check(game.player_hud.reward_inbox.capture_storage_snapshot()==FileAccess.get_file_as_bytes(DIR+"rewards.bin"),"exact mined iron copper and stone rewards survive fresh process")
		check(game.player_hud.capture_snapshot()==FileAccess.get_file_as_bytes(DIR+"inventory.bin"),"claimed resources and crafted materials survive fresh process")
		var retained: PackedByteArray=game.player_hud.reward_inbox.capture_storage_snapshot()
		for material in [8,9]:
			var point: Vector3=found[material]
			game.player.position=point+Vector3(0,2,0);game.terrain.focus=game.player.position
			check(game.terrain.sculpt_sphere(point,2,false),"repeat saved excavation admitted")
			deadline=Time.get_ticks_msec()+20000
			while game.terrain.pending_edit and Time.get_ticks_msec()<deadline:await process_frame
			check(not game.terrain.pending_edit and game.player_hud.reward_inbox.capture_storage_snapshot()==retained,"saved empty ore cavity grants no duplicate rewards")
	else:
		for material in [8,9]:
			var point: Vector3=found[material]
			game.player.position=point+Vector3(0,2,0);game.terrain.focus=game.player.position
			var before:=pending(game.player_hud)
			check(game.terrain.sculpt_sphere(point,2,false),"actual gameplay admits mining material %d"%material)
			deadline=Time.get_ticks_msec()+20000
			while game.terrain.pending_edit and Time.get_ticks_msec()<deadline:await process_frame
			var outcome: Dictionary=game.terrain.last_edit_outcome
			var counts: PackedInt64Array=outcome.get("removed_samples",PackedInt64Array())
			check(not game.terrain.pending_edit and counts.size()==16 and counts[material]>0,"published excavation removes selected ore %d"%material)
			var after:=pending(game.player_hud);var exact:=counts.size()==16
			if exact:
				for pair in [[201,counts[0]+counts[1]],[202,counts[8]],[203,counts[9]]]:exact=exact and after.get(pair[0],0)-before.get(pair[0],0)==pair[1]
			check(exact,"reward inbox receives exact native material counts")
			rows.append({"material":material,"point":[point.x,point.y,point.z],"removed":counts,"pending":after})
		for item in [202,203]:
			check(game.player_hud.reward_inbox.claim(game.player_hud.inventory,PackedInt64Array([item,2]),game.player_hud.inventory.snapshot().revision).ok,"claim mined ore %d"%item)
			check(preload("res://addons/player_runtime/crafting.gd").craft(game.player_hud.inventory,2 if item==202 else 3,1,game.player_hud.inventory.snapshot().revision).ok,"craft mined ore into metal")
		var f:=FileAccess.open(DIR+"rewards.bin",FileAccess.WRITE);f.store_buffer(game.player_hud.reward_inbox.capture_storage_snapshot());f.close()
		f=FileAccess.open(DIR+"inventory.bin",FileAccess.WRITE);f.store_buffer(game.player_hud.capture_snapshot());f.close()
	game.shutdown_requested=true;check(await game.terrain.shutdown_after_edits(),"normal combined save completes")
	var report:={"failures":failures,"rows":rows,"slot":game.terrain.save_slot,"scope":"Actual gameplay worker mines seeded iron and copper, claims/crafts rewards and reloads saved inventory. Fixture locates buried veins directly; natural discovery, visible ore face and access route remain unqualified."}
	var f:=FileAccess.open(DIR+("reopen.json" if reopen else "create.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	game.free();await process_frame;quit(1 if failures else 0)
