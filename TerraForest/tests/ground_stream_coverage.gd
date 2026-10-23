# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
 var native=ClassDB.instantiate("NativeGroundCover")
 var failures:=0;var maximum:=0;var legacy_gaps:=0
 for x in range(0,32,2):
  for z in range(0,32,2):
   var eye:=Vector3(960+x,3,960+z)
   var view:Dictionary=native.wanted_view(eye,Vector3.FORWARD,75,16.0/9.0,true)
   var legacy:Dictionary=native.wanted_view(eye,Vector3.FORWARD,75,16.0/9.0)
   maximum=maxi(maximum,view.cells.size())
   if view.cells.size()>121 or view.range!=124.0:failures+=1
   for angle in range(0,360,3):
    var point:=eye+Vector3(cos(deg_to_rad(angle)),0,sin(deg_to_rad(angle)))*148.0
    var key:=Vector2i(floori(point.x/32),floori(point.z/32))
    if not view.cells.has(key):failures+=1
    if not legacy.cells.has(key):legacy_gaps+=1
 for eye in [Vector3.ZERO,Vector3(1999,0,1999),Vector3(0,0,1999)]:
  var view:Dictionary=native.wanted_view(eye,Vector3.FORWARD,75,16.0/9.0,true)
  for key:Vector2i in view.cells:
   if key.x<0 or key.y<0 or key.x>62 or key.y>62:failures+=1
 print("GROUND_STREAM_COVERAGE failures=",failures," max_owners=",maximum," legacy_missing_probes=",legacy_gaps)
 quit(1 if failures else 0)
