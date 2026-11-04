# SPDX-License-Identifier: 0BSD
extends "res://tests/pickaxe_side_strike.gd"
func run()->void:
	var body:=CharacterBody3D.new();root.add_child(body)
	var tools:=preload("res://addons/player_runtime/tool_view.gd").new();root.add_child(tools);tools.set_process(false)
	var view:Node3D=tools.human;view.set_process(false);view.body=body
	var ends:Array=[];view.item_use_finished.connect(func(identity:int,cancelled:bool):ends.append([identity,cancelled]))
	for item in [214,215,216,217,218,219,102,601,9001]:
		tools.equip(item)
		check(view.held_item.visible and view.held_item.mesh!=null and view.active_clip=="FP_Item_Equip","owned/future item %d appears during its keyed equip"%item)
		check(view.body_mesh.mesh==view.unarmed_body_mesh and tools.attack_profile().is_empty(),"generic item %d uses repaired hands without becoming a weapon"%item)
		check(not tools.begin_item_use(item),"item %d cannot use before equip finishes"%item)
		view._process(.6)
		check(view.active_clip=="FP_Item_Hold" and tools.begin_item_use(item),"item %d holds and starts one use gesture"%item)
		check(not tools.begin_item_use(item+1),"item %d cannot restart its active gesture"%item)
		view._process(.65);check(view.item_use_identity==item,"item %d stays in the hand during use"%item)
		view._process(.8);check(ends[-1]==[item,false] and view.item_use_identity==0,"item %d emits one completed gesture"%item)
	tools.equip(218);view._process(.6);check(tools.begin_item_use(991),"cancellable item-use begins")
	tools.equip(6);view._process(2)
	check(ends[-1]==[991,true] and not view.held_item.visible and view.torch_effects.burning,"switch to torch cancels generic use and hides its object")
	tools.equip(0);check(not view.held_item.visible,"empty hand has no fallback object")
	tools.equip(218);view._process(.6);body.velocity=Vector3(0,0,5.5);view.set_third_person(true);view._process(.1)
	check(view.active_clip=="FP_Item_Walk","third-person item carry preserves existing leg locomotion")
	view.crouched=true;view._process(.1);check(view.active_clip=="FP_Item_Crouch","third-person crouch retains the held object")
	tools.free();body.free();print("ITEM_HOLD_INTEGRATION checks=",checks," failures=",failures);quit(1 if failures else 0)
