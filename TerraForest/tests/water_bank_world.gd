# SPDX-License-Identifier: 0BSD
extends "res://tests/water_raised_world.gd"
func run():
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Normal disposable world ready")
 if failures:await finish();return
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var center:Vector3=entry.seed;center.y=entry.level
 var bank:=Vector3.INF
 for step in range(1,81):
  var p:Vector3=center+Vector3(step*.25,0,0)
  var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*4,p-Vector3.UP*4,1))
  if not hit.is_empty() and hit.position.y>entry.level+.15 and hit.position.y<entry.level+.9:
   bank=hit.position;break
 check(bank.is_finite(),"Find actual terrain bank just above lake level")
 if failures:await finish();return
 var source:Vector3=bank-Vector3(1.5,0,0);source.y=entry.level
 var original:=amounts(game.lakes.capture_snapshot())
 aim(source);click(MOUSE_BUTTON_LEFT)
 check(await wait_publication() and held_ml()==1000000,"Scoop water beside the bank")
 var hole:=amounts(game.lakes.capture_snapshot())
 aim(bank)
 var start:Vector3=game.camera.global_position
 var hit:Dictionary=game.structures.blocks.raycast_scene(start,start-game.camera.global_basis.z*3.5,0xFFFFFFFF,[game.player.get_rid()])
 check(not hit.is_empty(),"Normal pour ray hits terrain")
 if failures:await finish();return
 var end:Vector3=hit.position+hit.normal*.01
 check(not game.lakes.water.raycast_surface(start,end).hit and not game.lakes.water.raycast_vacancy(start,end).hit,"Bank aim bypasses lake and scooped hole")
 print("BANK_WORLD source=",source," terrain=",hit.position)
 click(MOUSE_BUTTON_RIGHT)
 check(await wait_publication() and held_ml()==0,"Bank placement completes through normal input")
 var current:=amounts(game.lakes.capture_snapshot());var untouched:=true
 for p in original:
  if original[p]>hole.get(p,0):untouched=untouched and current.get(p,0)==hole.get(p,0)
 check(untouched,"Pour on bank does not refill the nearby scooped hole")
 game.fly=true;game._clear_motion();game.set_process(false);game.set_physics_process(false)
 game.camera.global_position=bank+Vector3(2,1.5,2);game.camera.look_at(bank,Vector3.UP)
 for frame in 3:await process_frame
 await photo("res://reports/water_bank_world.png")
 await finish()
func finish():
 if game!=null:game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_BANK_WORLD failures=",failures);quit(failures)
