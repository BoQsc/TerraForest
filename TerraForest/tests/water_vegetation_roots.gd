# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():call_deferred("run")
func run():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var trailer_size:=4+512*4+4*36
 var data:=PackedByteArray();data.resize(32+catalog.size()+9076+trailer_size);data.fill(0)
 data.encode_u32(0,0x31575256);data.encode_u32(4,6);data.encode_u32(8,catalog.size());data.encode_u32(12,1);data.encode_u64(16,41667);data.encode_u64(24,trailer_size)
 for i in catalog.size():data[32+i]=catalog[i]
 var base:int=32+catalog.size();data.encode_u64(base,(10<<24)|(10<<12)|10);data.encode_u32(base+8,1);data.encode_u32(base+12,1)
 for i in 512:data.encode_u16(base+18+i*12,500)
 for i in 729:data.encode_float(base+6160+i*4,1.0)
 var cell:=3+8*3+64*3;data.encode_u64(base+20+cell*12,41667)
 var at:=base+9076;data.encode_u32(at,1);at+=4
 var count_at:=0
 var corners:=[Vector3(0,0,0),Vector3(1,0,0),Vector3(1,1,0),Vector3(0,1,0)]
 for i in 512:
  data.encode_u32(at,4 if i==cell else 0)
  if i==cell:count_at=at
  at+=4
  if i!=cell:continue
  for j in 4:
   for point:Vector3 in [corners[j],corners[(j+1)%4],Vector3(0.5,0.5,250)]:
    data.encode_float(at,point.x);data.encode_float(at+4,point.y);data.encode_float(at+8,point.z);at+=12
 var water=ClassDB.instantiate("NativeRegionalWater")
 check(water.restore_snapshot(data),"Terrain contact triangle cache restores")
 var shape:Dictionary=water.cell_geometry(Vector3(41.75,41.75,41.75))
 # Pyramid volume: base 0.25 m² * height 0.25 m / 3 = 20.8333 L.
 # Air below height 0.25 m: 62.5 - 20.8333 = 41.6667 L.
 check(shape.capacity_ml==104166 and absf(shape.head-41.7500013333)<0.00001,"Analytic pyramid volume sets the correct water height rather than interpolating four flat corners")
 check(absf(shape.bottom-41.75)<0.000001 and absf(water.cell_geometry(Vector3(41.5,41.75,41.5)).bottom-41.5)<0.000001,"Contact retains the interior terrain peak and corner heights")
 var roots:Array[Transform3D]=[
  Transform3D(Basis.IDENTITY,Vector3(41.6,41.57,41.6)),
  Transform3D(Basis.IDENTITY,Vector3(41.75,41.8,41.75)),
  Transform3D(Basis.IDENTITY,Vector3(43,41.57,43))]
 check(water.depth_at(roots[0].origin)==0 and water.depth_at(roots[0].origin+Vector3.UP*.08)>0,"Buried root reproduces dry-origin/wet-shoot mismatch")
 check(water.placement_mask(roots)==PackedByteArray([1,0,0]),"Vegetation rejects submerged buried roots while preserving above-water and dry roots")
 print("WATER_VEGETATION_ROOTS failures=",failures);quit(failures)
