# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func _initialize():call_deferred("run")
func run():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 var water=ClassDB.instantiate("NativeRegionalWater")
 var bytes:=FileAccess.get_file_as_bytes("res://tests/fixtures/water_contact_clip/captured.bin")
 if not water.restore_snapshot(bytes):push_error("Fixture restore failed");quit(1);return
 var quantity:int=water.statistics().water_ml;var samples:=0;var penetrations:=0;var minimum:=INF
 var target:=Vector3(802.0,49.49169921875,1306.5)
 for step in 1000:
  var packet:Dictionary=water.next_mesh()
  if packet.is_empty():break
  var points:PackedVector3Array=packet.arrays[Mesh.ARRAY_VERTEX]
  for i in range(0,points.size(),3):
   var a:Vector3=points[i];var b:Vector3=points[i+1];var c:Vector3=points[i+2]
   if (c-a).cross(b-a).y<=0:continue
   var point:Vector3=(a+b+c)/3.0
   if point.distance_to(target)>3:continue
   var geometry:Dictionary=water.cell_geometry(point)
   if geometry.is_empty():continue
   var gap:float=point.y-geometry.bottom;samples+=1;minimum=minf(minimum,gap)
   if gap< -0.00025:penetrations+=1
 var passed:bool=samples>0 and penetrations==0 and water.statistics().water_ml==quantity
 print("PASS " if passed else "FAIL ","Captured natural-ground surface stays outside its exact terrain contact; samples=",samples," penetrations=",penetrations," min_gap=",minimum)
 failures=0 if passed else 1
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/water_contact_clip.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"samples":samples,"penetrations":penetrations,"minimum_gap_m":minimum,"water_ml":quantity}));file.close()
 print("WATER_CONTACT_CLIP failures=",failures);quit(failures)
