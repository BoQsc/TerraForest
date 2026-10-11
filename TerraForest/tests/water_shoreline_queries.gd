# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String):
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func density(p: Vector3) -> float:
 return p.y-(2.0+((p.x-16)*(p.x-16)+(p.z-16)*(p.z-16))/20.0)
func _initialize():
 var lake=ClassDB.instantiate("NativeLakeVolume")
 check(lake.configure(Vector3.ZERO,Vector3i(32,12,32),1,8,Vector3(12,6,16)),"configure analytic curved basin")
 var field=PackedFloat32Array()
 for z in 33:
  for y in 13:
   for x in 33:field.append(density(Vector3(x,y,z)))
 check(lake.bake_density(field)==1,"bake analytic basin")
 var arrays: Array=lake.smooth_surface_arrays()
 var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
 var identity=PackedByteArray();identity.resize(32)
 var restored=ClassDB.instantiate("NativeLakeVolume")
 check(restored.restore_bake(lake.capture_bake(identity),identity),"restore same baked representation")
 var rows: Array=[];var examples: Array=[];var same=true;var total_missing=0
 for depth in [.1,.6,1.1,2.0]:
  var samples=0;var missing=0
  for i in range(0,indices.size(),3):
   var a: Vector3=vertices[indices[i]];var b: Vector3=vertices[indices[i+1]];var c: Vector3=vertices[indices[i+2]]
   for weight in [Vector3(1.0/3,1.0/3,1.0/3),Vector3(.6,.2,.2),Vector3(.2,.6,.2),Vector3(.2,.2,.6)]:
    var point=a*weight.x+b*weight.y+c*weight.z-Vector3.UP*depth
    # Only test visible surface triangles above actual analytic free space.
    # Positive margin avoids reporting points on/in solid ground as missing water.
    if density(point)<=.05:continue
    samples+=1
    var wet: bool=lake.contains(point)
    same=same and restored.contains(point)==wet
    if not wet:
     missing+=1
     if examples.size()<12:examples.append({"point":[point.x,point.y,point.z],"depth":depth,"air_margin":density(point)})
  total_missing+=missing
  rows.append({"depth":depth,"visible_air_samples":samples,"dry_queries":missing})
 check(same,"cold and restored query classifications agree")
 check(not lake.contains(Vector3(0,7,0)) and not lake.contains(Vector3(16,1,16)),"outside basin and solid floor stay dry")
 check(total_missing==0,"visible water above free space agrees with immersion queries")
 var grid: Array=[]
 for z in 128:
  for x in 128:
   var point=Vector3((x+.5)*.25,6.9,(z+.5)*.25)
   grid.append(0 if density(point)<=.05 else 1 if lake.contains(point) else 2)
 var report={"failures":failures,"rows":rows,"grid":{"width":128,"depth_below_surface":1.1,"step_m":.25,"values":grid},"examples":examples,"stats":lake.statistics(),"scope":"Analytic curved basin, triangle samples in free space; diagnostic sample counts are not area percentages or full-world performance evidence"}
 DirAccess.make_dir_recursive_absolute("res://reports/water_shoreline_queries")
 var file=FileAccess.open("res://reports/water_shoreline_queries/result.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 print(JSON.stringify(report));print("WATER_SHORELINE_QUERIES failures=",failures);quit(1 if failures else 0)
