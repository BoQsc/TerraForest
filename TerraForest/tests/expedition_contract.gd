# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	for path:String in ["demo/world.gd","demo/worlds.gd","addons/player_runtime/quest_world.gd","addons/player_runtime/trader_panel.gd","addons/player_runtime/trader_ride.gd","addons/world_runtime/generate_world_task.gd","addons/characters/runtime/zombie.gd"]:
		var script:Script=load("res://"+path)
		check(script!=null and script.can_instantiate(),"production script parses: "+path)
	var recipe:RefCounted=ClassDB.instantiate("NativeWorldRecipe")
	var options:Dictionary=preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS.duplicate()
	var bytes:PackedByteArray=recipe.encode(options)
	check(bytes.size()==40 and bytes.decode_u32(4)==7 and recipe.decode(bytes)==options,"default expedition recipe round-trips")
	var old:=options.duplicate();old.erase("introduction")
	var legacy:PackedByteArray=recipe.encode(old)
	check(legacy.size()==36 and not recipe.decode(legacy).has("introduction"),"old worlds do not acquire an introduction")
	var browser:Control=load("res://demo/worlds.tscn").instantiate();root.add_child(browser)
	check(browser.selected_options()==options,"normal browser defaults match native generation recipe")
	var asset:Resource=load("res://addons/structures/prefabs/expansion_trader_t1_e2.tres")
	var access:Array=preload("res://addons/structures/terrain_lot_planner.gd").access_segments({"asset":asset,"origin":Vector3i.ZERO,"rotation":0,"entrance":{"segment":{"start":Vector3(0,6,0),"finish":Vector3(0,0,30),"half_width":1.5}}})
	check(access.size()==2 and is_equal_approx(access[0].start.y,6) and access[0].start.y==access[0].finish.y and is_equal_approx(access[0].start.distance_to(access[0].finish),1.5),"approach targets the finished floor level outside its authoritative soil-clearance mask")
	check(access[1].start==access[0].finish and access[1].finish==Vector3(0,0,30),"survey and bake use the same connected landing and slope")
	var short_access:Array=preload("res://addons/structures/terrain_lot_planner.gd").access_segments({"asset":asset,"origin":Vector3i.ZERO,"rotation":0,"entrance":{"segment":{"start":Vector3(0,0,0),"finish":Vector3(0,0,2),"half_width":1.5}}})
	check(short_access.size()==2 and short_access[0].start.distance_to(short_access[0].finish)>=1 and short_access[1].start.distance_to(short_access[1].finish)>=1,"short landing preserves native minimum edit-segment length")
	browser.queue_free();await process_frame
	var skeleton:=Skeleton3D.new();root.add_child(skeleton);skeleton.modifier_callback_mode_process=Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var parts:Dictionary={}
	for index in 14:
		var name:String="torso" if index==0 else "part_"+str(index)
		skeleton.add_bone(name);skeleton.set_bone_rest(index,Transform3D(Basis.IDENTITY,Vector3(0,.1*index,0)))
		parts[name]={"bone":name}
	var reaction:Node=ClassDB.instantiate("NativeZombieHitReaction");skeleton.add_child(reaction)
	check(reaction.configure(parts) and not reaction.is_active(),"bounded modifier starts asleep")
	check(not reaction.hit("missing",Vector3.ZERO,Vector3.BACK,20) and not reaction.hit("torso",Vector3(NAN,0,0),Vector3.BACK,20),"invalid hits cannot activate modifier")
	check(reaction.hit("part_1",Vector3(0,.4,0),Vector3.BACK*2,30),"localized bullet impulse accepted")
	skeleton.advance(1.0/60);await process_frame
	check(reaction.statistics().maximum_angle>0 and reaction.statistics().energy>0,"bullet creates nonstatic deflection")
	var bounded:=true
	for frame in 120:
		reaction.hit("part_1",Vector3(0,.4,0),Vector3.BACK*2,30)
		skeleton.advance(1.0/60);await process_frame
		bounded=bounded and reaction.statistics().maximum_angle<=.481
	check(bounded,"sustained automatic fire remains angularly bounded")
	for frame in 180:skeleton.advance(1.0/60);await process_frame
	check(not reaction.is_active() and reaction.statistics().energy==0,"spring settles and disables itself after gunfire")
	reaction.hit("torso",Vector3.UP,Vector3.BACK,30);reaction.clear()
	check(not reaction.is_active() and reaction.statistics().energy==0,"death cleanup stops all living-pose forces")
	skeleton.free()
	print("EXPEDITION_CONTRACT checks=",checks," failures=",failures);quit(1 if failures else 0)
