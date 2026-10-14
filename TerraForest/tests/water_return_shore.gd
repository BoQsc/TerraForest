# SPDX-License-Identifier: 0BSD
extends "res://tests/water_bucket_roundtrip.gd"
func run():
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Actual lake review ready")
 if failures:await finish();return
 var original:Dictionary=amounts(game.lakes.capture_snapshot())
 var transform:Transform3D=game.camera.global_transform
 results.cases=[]
 for offset:float in [0.5,-0.5]:
  game.camera.global_transform=transform
  var scoop:Dictionary=await measured_click(MOUSE_BUTTON_LEFT)
  check(scoop.ready and held_ml()==1000000,"Actual shore click collects one unit")
  game.camera.global_position+=Vector3(offset,0,0)
  var poured:Dictionary=await measured_click(MOUSE_BUTTON_RIGHT)
  var current:Dictionary=amounts(game.lakes.capture_snapshot())
  check(poured.ready and held_ml()==0,"Shifted shore click returns one unit")
  check(current==original,"Shifted return restores original lake cells without a pillar")
  results.cases.append({"offset":offset,"same_cells":current==original,"pour":poured})
  for frame in 4:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/water_return_shore_%s.png"%str(offset))
  if failures:break
 await finish()
func finish():
 results.failures=failures
 var file:=FileAccess.open("res://reports/water_return_shore.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_RETURN_SHORE failures=",failures);quit(failures)
