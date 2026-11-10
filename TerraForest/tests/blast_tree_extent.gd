# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func masks(ids:PackedInt64Array)->PackedByteArray:
	var result:=PackedByteArray()
	for first in range(0,ids.size(),4096):result.append_array(game.ecosystem.harvest_state.mask(ids.slice(first,first+4096)))
	return result
func run()->void:
	var slot:="recipe_generated_4644d8cfc8f97e43"
	var save:="user://worlds/"+slot+".trw"
	var checksum:=FileAccess.get_sha256(save)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(PackedStringArray(["--world-slot="+slot,"--snapshot-readonly","--gameplay-construction","--ground-cover","--temporary","--no-derived-cache"]),true)
	game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	var deadline:=Time.get_ticks_msec()+120000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"existing forest fixture loads read-only")
	if failures:await finish();return
	game.set_physics_process(false);game.player_view.entry.finish();game.player.set_physics_process(false)
	deadline=Time.get_ticks_msec()+15000
	while (game.ecosystem._samples.is_empty() or not game.ecosystem._requests.is_empty()) and Time.get_ticks_msec()<deadline:await process_frame
	var roots:Dictionary={};var nearest:=INF;var centre:=Vector3.INF
	for sample:Dictionary in game.ecosystem._samples.values():
		for index in sample.active.size():
			var point:Vector3=sample.active_transforms[index].origin+Vector3.UP*.2
			roots[sample.active[index]]=point
			var distance:float=point.distance_squared_to(game.player.global_position)
			if distance<nearest:nearest=distance;centre=point
	check(centre.is_finite() and roots.size()>1,"resident tree identities available for blast audit")
	if failures:await finish();return
	var old_mask:PackedByteArray=masks(PackedInt64Array(roots.keys()))
	game.combat.set_physics_process(false)
	var base:=centre-Vector3.UP*.2
	var barrel:int=game.combat.barrels.insert_instance(PackedFloat32Array([1,0,0,base.x,0,1,0,base.y,0,0,1,base.z]),AABB())
	check(barrel>0 and game.combat.detonate(barrel),"actual barrel explosion admitted beneath a tree")
	deadline=Time.get_ticks_msec()+45000
	while (game.terrain.pending_edit or not game.combat.blast_jobs.is_empty()) and Time.get_ticks_msec()<deadline:
		game.combat.step_blasts();await process_frame
	check(not game.terrain.pending_edit,"blast publication and native support checks complete")
	var ids:=PackedInt64Array(roots.keys());var new_mask:PackedByteArray=masks(ids)
	check(old_mask.size()==ids.size() and new_mask.size()==ids.size(),"bounded native identity batches cover the forest")
	if failures:await finish();return
	var destroyed:=0;var farthest:=0.0;var far:=0
	for index in ids.size():
		if old_mask[index]!=0 or new_mask[index]==0:continue
		destroyed+=1
		var point:Vector3=roots[ids[index]];var distance:=Vector2(point.x-centre.x,point.z-centre.z).length()
		farthest=maxf(farthest,distance)
		if distance>4.5:far+=1
	print("BLAST_TREE_EXTENT roots=",roots.size()," destroyed=",destroyed," farthest_horizontal_m=",farthest," outside_radius_plus_lattice=",far)
	check(destroyed>0 and far==0,"support removal does not destroy distant tree identities")
	for frame in 8:await process_frame
	var missing:=0
	for id:int in roots:
		var point:Vector3=roots[id]
		if Vector2(point.x-centre.x,point.z-centre.z).length()>4.5 and not game.vegetation.renderer.roots.has(id):missing+=1
	check(missing==0,"distant tree renderer identities survive the complete blast")
	check(FileAccess.get_sha256(save)==checksum,"source forest save remains unchanged")
	await finish()
func finish()->void:
	if is_instance_valid(game):game.terrain.shutdown();game.free()
	await process_frame;await process_frame
	print("BLAST_TREE_EXTENT failures=",failures);quit(1 if failures else 0)
