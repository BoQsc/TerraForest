# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:run.call_deferred()
func run()->void:
 var state=ClassDB.instantiate("NativeCombatState")
 check(state.load_rounds(15,9) and not state.load_rounds(1,9),"PX9 enforces its own 15-round capacity")
 check(state.load_rounds(7,7) and state.load_rounds(12,8) and state.take_round(9),"three independent magazines")
 var saved:PackedByteArray=state.capture_storage_snapshot()
 var restored=ClassDB.instantiate("NativeCombatState")
 check(restored.restore_storage_snapshot(saved) and restored.get_rounds(9)==14 and restored.get_rounds(7)==7 and restored.get_rounds(8)==12,"v4 round trip preserves all magazines")
 var invalid:=saved.duplicate();invalid.encode_u32(24,16)
 check(not restored.restore_storage_snapshot(invalid) and restored.get_rounds(9)==14,"corrupt pistol capacity rejected atomically")
 var legacy:=saved.slice(0,24);legacy.encode_u32(4,3);legacy.append_array(saved.slice(28))
 check(restored.restore_storage_snapshot(legacy) and restored.get_rounds(9)==0 and restored.get_rounds(8)==12,"v3 saves initialize handgun empty")
 var inventory=preload("res://addons/player_runtime/item_catalog.gd").create_inventory()
 check(inventory.grant(9,1,inventory.snapshot().revision).ok and inventory.grant(228,30,inventory.snapshot().revision).ok,"handgun and matching cartridges use shared native catalog")
 var tools=load("res://addons/player_runtime/tool_view.gd").new();root.add_child(tools)
 tools.set_process(false);tools.human.set_process(false)
 var human:Node=tools.human
 var original:Mesh=human.body_mesh.mesh
 var split=preload("res://addons/player_runtime/first_person_meshes.gd").new();split.prepare(tools);split.set_active(true)
 tools.hide();human._process(.016)
 check(not human.animation_player.active,"hidden ordinary item suspends the base animation mixer")
 tools.equip(9)
 tools.show();human._process(.016)
 check(human.animation_player.active,"handgun restores the base mixer after a hidden item switch")
 check(human.px9!=null and human.px9.motion!=null,"exact Human R11 rest contract admits paired PX9 adapter")
 if human.px9==null or human.px9.motion==null:tools.free();quit(1);return
 check(human.body_mesh.mesh!=original,"PX9 selects corrected hand skin")
 split.sync()
 check(split.pairs[0].arms.mesh==preload("res://addons/characters/runtime/px9/first_person_arms.res") and human.body_mesh.mesh==preload("res://addons/characters/runtime/px9/first_person_body.res"),"live first-person renderer selects corrected PX9 arms and body")
 check(split.equipment.size()>0,"equipment registered with first-person depth renderer")
 var events:Array=[];var completed:Array=[]
 human.handgun_event.connect(func(event:String,_data:Dictionary):events.append(event))
 human.rifle_reload_finished.connect(func():completed.append(true))
 human._process(1)
 for action:Dictionary in human.px9.motion.definition.actions:
  check(human.px9.request(action.id)==OK,"paired clip available: "+action.id)
  human.px9.motion.seek_frame(action.frame_end*.5)
  check(is_equal_approx(human.px9.motion.human_player.current_animation_position,human.px9.motion.item_player.current_animation_position),"human and mechanics share clock: "+action.id)
 human.px9.request("idle_empty");human.action_remaining=0
 check(human.rifle_action("Reload"),"empty handgun reload starts")
 human._process(.9)
 check(completed.is_empty() and events.has("magazine_out"),"authored magazine-out event precedes reload completion")
 human.cancel_rifle_reload();human._process(4)
 check(completed.is_empty(),"cancelled handgun reload never grants ammunition")
 check(human.rifle_action("Reload"),"reload restarts after cancellation")
 human._process(3.3)
 check(completed.size()==1,"reload finishes exactly once")
 human.handgun_empty=false;human.rifle_aiming=false;human._process(.2)
 check(human.rifle_action("HipFire"),"hip shot begins independent aim test")
 human._process(.05)
 human.rifle_aiming=true;human._process(.04)
 check(human.px9.motion.current_action=="fire" and is_equal_approx(human.px9.motion.time_seconds,.09) and human.handgun_aim.weight>0,"aim responds within recoil without restarting or delaying the shot clock")
 var aim_weight:float=human.handgun_aim.weight
 var skeleton:Skeleton3D=human.px9.attachment.get_skeleton()
 var hand:int=skeleton.find_bone("RightHand")
 skeleton.force_update_all_bone_transforms()
 var blended:Vector3=skeleton.get_bone_global_pose(hand).origin
 human.handgun_aim.weight=0;human.handgun_aim.advance(0,false,human.px9.motion)
 skeleton.force_update_all_bone_transforms()
 check(blended.distance_to(skeleton.get_bone_global_pose(hand).origin)>.001,"aim layer actually moves the firing hand during unfinished hip recoil")
 human.handgun_aim.weight=aim_weight
 human.rifle_aiming=false;human._process(.02)
 check(human.px9.motion.current_action=="fire" and human.handgun_aim.weight<aim_weight and is_equal_approx(human.px9.motion.time_seconds,.11),"aim reversal responds during the same uninterrupted recoil")
 human._process(.4)
 human.handgun_empty=false;human.rifle_aiming=true;human._process(.1);human._process(.4)
 check(human.px9.motion.current_action=="aim_idle","right mouse enters aimed hold")
 human.handgun_empty=true;human.action_remaining=0
 check(human.rifle_action("Fire"),"last aimed shot starts")
 human._process(.45)
 check(human.px9.motion.current_action=="aim_idle_empty" or human.px9.motion.current_action=="idle_empty","last round holds slide open")
 check(events.has("shot") and events.has("case_eject") and events.has("slide_locked"),"shot, casing and slide-lock events remain paired")
 tools.equip(1);check(human.px9.motion.current_action=="holster","tool switch plays handgun holster")
 human._process(1)
 check(human.current==1 and human.px9==null and human.body_mesh.mesh==human.original_body_mesh,"unequip restores original body and next tool")
 check(preload("res://addons/audio_runtime/wav_decoder.gd").decode("res://addons/audio_runtime/packs/Kaino/1/Pistol Shot 1 - Kaino.wav")!=null,"existing pistol recording decodes")
 split.dispose()
 tools.free();await process_frame
 print("PX9_HANDGUN checks=",checks," failures=",failures);quit(1 if failures else 0)
