# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize():
 var reference:=Image.load_from_file("res://reports/water_underwater_reference.png")
 var before:=Image.load_from_file("res://reports/water_underwater_before.png")
 var after:=Image.load_from_file("res://reports/water_underwater_after.png")
 if reference==null or before==null or after==null:quit(1);return
 var old_error:=0.0;var new_error:=0.0;var samples:=0
 # Lake floor only: exclude the actual water/air surface, HUD and held item.
 for y in range(440,850,4):
  for x in range(80,1250,4):
   var r:=reference.get_pixel(x,y);var b:=before.get_pixel(x,y);var a:=after.get_pixel(x,y)
   old_error+=absf(b.r-r.r)+absf(b.g-r.g)+absf(b.b-r.b)
   new_error+=absf(a.r-r.r)+absf(a.g-r.g)+absf(a.b-r.b);samples+=3
 old_error=old_error*255/samples;new_error=new_error*255/samples
 var ok:=old_error>1.0 and new_error<old_error*0.2
 var report:Dictionary={"failures":0 if ok else 1,"before_mean_rgb_error":old_error,"after_mean_rgb_error":new_error,"reference":"Same underwater fog and camera, water meshes hidden; lake-floor ROI excludes free surface and UI", "scope":"One fixed underwater viewpoint, not all viewing angles or edited topology"}
 var file:=FileAccess.open("res://reports/water_underwater_pixels.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 print(JSON.stringify(report));print("WATER_UNDERWATER_PIXELS failures=",0 if ok else 1);quit(0 if ok else 1)
