extends SceneTree

var game:Node
var checks:=0
var failures:=0
var folder:="res://reports/harvest_hits_world"
func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->bool:
	checks+=1;print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
	return condition
func frames(count:int=3)->void:
	for frame in count:await process_frame
func until(predicate:Callable,seconds:int)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func amount(item:int)->int:
	var count:=0
	for row:Dictionary in game.player_hud.inventory.snapshot().slots:
		if row.item==item:count+=row.count
	return count
func photo(label:String)->void:
	await frames();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label+".png"))==OK,"capture "+label)
func cover_target(species:int)->Dictionary:
	var cover:Node=game.ground_cover
	for cell:Vector2i in cover.resident:
		if cover._dirty.has(cell) or cover._pending.has(cell):continue
		var row:Dictionary=cover.resident[cell][species]
		for index:int in row.ids.size():
			if row.ids[index]>=4294967296:continue
			var offset:=index*12
			var point:=Vector3(row.transforms[offset+3],row.transforms[offset+7],row.transforms[offset+11])
			game.camera.global_position=point+Vector3(.05,1.3,.05);game.camera.look_at(point)
			var target:Dictionary=game.world_attack.target()
			if target.get("kind")=="cover" and target.id==row.ids[index] and not target.get("large",false):return target
	return {}
func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--navigation-evidence="):folder=argument.trim_prefix("--navigation-evidence=")
	folder=ProjectSettings.globalize_path(folder);DirAccess.make_dir_recursive_absolute(folder)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
	if not check(await until(func():return not game.loading_active and not game.needs_floor_spawn,65),"temporary harvest world becomes playable"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.zombies.population_enabled=false;game.zombies.clear();game.session_menu.set_open(false)
	var hud:CanvasLayer=game.player_hud;var attack:RefCounted=game.world_attack
	hud.resource_gains_allowed=func()->bool:return not hud.inventory_open and not game.session_menu.opened
	hud.equip_item(1);hud.refresh();game.tool_view.human.set_process(false)
	var point:Vector3=game.player.global_position+Vector3(0,7,0)
	var collection:Node3D=game.structures.model("resources/iron_outcrop/v1");var identity:=91001
	check(collection.upsert_transforms(PackedInt64Array([identity]),[Transform3D(Basis.IDENTITY,point)]),"actual mineral-stone model is installed in an isolated fixture")
	game.camera.global_position=point+Vector3(0,.05,2);game.camera.look_at(point);await frames(6)
	var target:Dictionary=attack.target()
	if not check(target.get("asset","")=="resources/iron_outcrop/v1" and target.id==identity,"normal pickaxe ray selects the mineral resource"):await finish();return
	var ore_before:=amount(202);var wear_before:int=hud.inventory.snapshot().slots[hud.active_slot].wear
	attack.next_attack=0
	check(attack.attack(),"harvesting starts through the authored attack animation")
	var profile:Dictionary=game.tool_view.attack_profile();game.tool_view.human._process(profile.contact-.01)
	check(amount(202)==ore_before and attack.durability.damage(target.key,target.health)==0,"windup grants no resources or damage before contact")
	game.tool_view.human._process(.02)
	check(amount(202)==ore_before+1 and attack.durability.damage(target.key,target.health)==30,"first real contact grants one matching ore while the stone survives")
	var contact:int=attack.pending.identity;attack.resolve_contact(contact)
	check(amount(202)==ore_before+1 and hud.inventory.snapshot().slots[hud.active_slot].wear==wear_before+1,"duplicate contact cannot grant extra resources or wear")
	game.tool_view.cancel_attack();await photo("first_ore_hit")
	check(hud.resource_feed.active.any(func(entry):return entry.item==202 and entry.icon.texture!=null),"per-hit gain uses the existing resource popup and item icon")
	var saved_damage:PackedByteArray=attack.durability.capture_storage_snapshot();var saved_items:PackedByteArray=hud.inventory.capture_storage_snapshot()
	check(attack.durability.restore_storage_snapshot(saved_damage) and hud.restore_snapshot(saved_items) and amount(202)==ore_before+1,"damage and reward restore together without replaying the paid hit")
	hud.equip_item(1)
	var filled:Dictionary=hud.inventory.snapshot()
	for index in range(1,32):filled.slots[index]={"item":101,"count":999,"wear":0,"water_ml":0}
	hud.inventory.restore(filled,hud.inventory.snapshot().revision);hud.refresh()
	var full:PackedByteArray=hud.inventory.capture_storage_snapshot()
	check(not attack.apply_target(target) and attack.durability.capture_storage_snapshot()==saved_damage and hud.inventory.capture_storage_snapshot()==full,"full bag refuses a paying hit without losing resources, health or tool durability")
	hud.restore_snapshot(saved_items);hud.equip_item(1)
	for strike in 10:check(attack.apply_target(target),"surviving resource hit accepted "+str(strike+2))
	check(amount(202)==ore_before+11 and not collection.get_instance(identity).is_empty(),"all eleven nonfatal pickaxe hits pay immediately")
	var damage_before:PackedByteArray=attack.durability.capture_storage_snapshot();var inventory_before:PackedByteArray=hud.inventory.capture_storage_snapshot()
	game.session_menu.set_open(true)
	check(not attack.apply_target(target) and attack.durability.capture_storage_snapshot()==damage_before and hud.inventory.capture_storage_snapshot()==inventory_before,"failed final destruction rolls back its provisional damage and resource payout")
	await frames(2)
	game.session_menu.set_open(false);hud.equip_item(1)
	var before_final:=amount(202)
	check(attack.apply_target(target) and amount(202)==before_final+10 and collection.get_instance(identity).is_empty(),"final mineral hit grants ten ore and removes the model once")
	check(not attack.apply_target(target) and amount(202)==ore_before+21,"stale destroyed resource cannot be farmed again")
	await photo("finishing_ore_reward")
	check(hud.resource_feed.active.any(func(entry):return entry.item==202 and entry.count==10),"finishing popup reports its ten-ore reward, without replaying rolled-back resources")
	game.ecosystem.set_process(false)
	var tree_id:=0
	for candidate in game.vegetation.renderer.roots:
		var owner:int=(candidate-1)/(game.ecosystem.GRID*game.ecosystem.GRID)
		var key:=Vector2i(owner%32,owner/32)
		if game.ecosystem._samples.has(key) and game.ecosystem._samples[key].active.has(candidate) and not game.ecosystem._pending_cells.has(key) and not game.ecosystem._reconcile.has(key) and not game.ecosystem._resample.has(key):tree_id=candidate;break
	if check(tree_id>0,"a live natural tree is available"):
		hud.equip_item(2);var wood_before:=amount(102)
		var tree:Dictionary={"kind":"tree","id":tree_id,"key":"tree:%d"%tree_id,"health":90,"material":"wood","name":"Tree"}
		check(attack.apply_target(tree) and amount(102)==wood_before+1 and game.vegetation.renderer.roots.has(tree_id),"first axe hit yields wood before felling the tree")
		check(attack.apply_target(tree) and amount(102)==wood_before+2,"second axe hit yields another wood")
		check(attack.apply_target(tree) and amount(102)==wood_before+8 and game.ecosystem.harvest_state.contains(tree_id),"final axe hit yields six wood and preserves normal persistent felling")
		check(not attack.apply_target(tree) and amount(102)==wood_before+8,"felled tree cannot be harvested again from a stale hit")
	check(attack.harvest_profile({"kind":"block"}).is_empty() and attack.harvest_profile({"kind":"cover","id":4294967296,"species":0}).is_empty() and attack.harvest_profile({"kind":"tree","id":4294967296}).is_empty(),"built blocks and player-authored vegetation do not generate per-hit resources")
	check(await until(func():return not cover_target(0).is_empty() and not cover_target(6).is_empty() and not cover_target(8).is_empty(),40),"ground cover finishes its post-felling reconciliation before harvesting fixtures")
	game.ground_cover.set_process(false)
	for fixture:Dictionary in [{"species":0,"tool":1,"item":201,"total":3},{"species":6,"tool":2,"item":209,"total":3},{"species":8,"tool":2,"item":102,"total":4}]:
		var cover:=cover_target(fixture.species)
		if check(not cover.is_empty(),"live natural harvest target exists for species "+str(fixture.species)):
			hud.equip_item(fixture.tool);var before:=amount(fixture.item)
			check(attack.apply_target(cover) and amount(fixture.item)==before+1,"first hit pays before natural cover removal for species "+str(fixture.species))
			check(attack.apply_target(cover) and amount(fixture.item)==before+fixture.total and game.ground_cover.removed.mask(PackedInt64Array([cover.id]))[0]!=0,"larger finishing reward removes natural cover exactly once for species "+str(fixture.species))
			check(not attack.apply_target(cover) and amount(fixture.item)==before+fixture.total,"stale harvested cover cannot pay again for species "+str(fixture.species))
	await finish()
func finish()->void:
	if game!=null:game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await frames(2)
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("HARVEST_HITS_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
