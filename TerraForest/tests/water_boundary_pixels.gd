# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize():
 var folder:="res://docs/evidence/water_shoreline_visual/"
 var report:Dictionary={}
 for version:String in ["before","after"]:
  var image:=Image.load_from_file(folder+version+"_0_0.png")
  var reference:=Image.load_from_file(folder+version+"_0_2.png")
  if image==null or reference==null:quit(1);return
  var error:=0.0;var samples:=0
  # Same-run lake-bed ROI, excluding free surface, bucket and HUD.
  for y in range(480,850,4):
   for x in range(80,1250,4):
    var a:=image.get_pixel(x,y);var b:=reference.get_pixel(x,y)
    error+=absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b);samples+=3
  report[version]=error*255/samples
 var ok:bool=report.after<.5 and report.after<report.before*.2
 report["failures"]=0 if ok else 1
 var file:=FileAccess.open(folder+"pixel_comparison.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 print(report);print("WATER_BOUNDARY_PIXELS failures=",report.failures);quit(report.failures)
