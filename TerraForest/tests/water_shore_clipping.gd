# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var bytes:=PackedByteArray();bytes.resize(32+catalog.size()+6160+729*4);bytes.fill(0)
 bytes.encode_u32(0,0x31575256);bytes.encode_u32(4,2);bytes.encode_u32(8,catalog.size());bytes.encode_u32(12,1);bytes.encode_u64(16,62500)
 for i in catalog.size():bytes[32+i]=catalog[i]
 var base:int=32+catalog.size();bytes.encode_u64(base,(10<<24)|(10<<12)|10);bytes.encode_u32(base+8,1);bytes.encode_u32(base+12,1);base+=16
 for i in 512:bytes.encode_u16(base+i*12,500);bytes.encode_u16(base+i*12+2,500)
 var wet:=3+8*3+64*3;bytes.encode_u16(base+wet*12,0);bytes.encode_u64(base+wet*12+4,62500)
 var samples:int=base+512*12
 for i in 729:
  var x:float=40.0+(i%9)*0.5;var y:float=40.0+((i/9)%9)*0.5
  bytes.encode_float(samples+i*4,y-(41.5+x-42.0))
 var water=ClassDB.instantiate("NativeRegionalWater")
 check(water.restore_snapshot(bytes),"terrain samples and quantities restore from version 2 cache")
 var before:PackedByteArray=water.capture_snapshot(catalog)
 var mesh:Dictionary=water.next_mesh();var v:PackedVector3Array=mesh.arrays[Mesh.ARRAY_VERTEX]
 var area:=0.0;var edge:=false;var valid:=true
 for i in range(0,v.size(),3):
  var center:Vector3=(v[i]+v[i+1]+v[i+2])/3.0
  if center.x>42.00001 and center.z>41.50001 and center.z<41.99999:
   area+=(v[i+1]-v[i]).cross(v[i+2]-v[i]).length()*0.5
   for j in 3:
    valid=valid and v[i+j].x<=42.25001 and abs(v[i+j].y-41.75)<0.00001
    edge=edge or abs(v[i+j].x-42.25)<0.00001
 check(valid and edge and abs(area-0.125)<0.00001,"shore triangles reach sloped terrain contour without entering solid half-cell")
 check(mesh.faces.shore_triangles>0 and water.capture_snapshot(catalog)==before,"shore reconstruction preserves exact authoritative volume and terrain cache")
 var corrupt:=bytes.duplicate();corrupt.encode_u32(samples,0x7fc00000)
 check(not water.restore_snapshot(corrupt) and water.capture_snapshot(catalog)==before,"non-finite cached terrain rejected without replacing live water")
 corrupt=bytes.slice(0,bytes.size()-4)
 check(not water.validate_snapshot(corrupt),"truncated terrain cache rejected")
 var open_air:=bytes.duplicate()
 for i in 729:open_air.encode_float(samples+i*4,1.0)
 var air_water=ClassDB.instantiate("NativeRegionalWater");check(air_water.restore_snapshot(open_air),"open-air control cache restores")
 check(air_water.next_mesh().faces.shore_triangles==0,"shore reconstruction never paints water into fully dry open-air cells")
 check(abs(water.depth_at(Vector3(42.1,41.7,41.75))-0.05)<0.00001,"depth query recognizes reconstructed shallow water")
 check(water.depth_at(Vector3(42.1,41.55,41.75))==0 and water.depth_at(Vector3(42.4,41.7,41.75))==0,"shore depth query excludes terrain and solid side")
 check(water.depth_at(Vector3(42.1,41.8,41.75))==0,"air above shoreline remains dry")
 GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
 var inventory=ClassDB.instantiate("NativePlayerInventory")
 for item in range(401,412):inventory.register_item(item,1)
 check(inventory.grant(401,1,0).ok,"real native inventory supplies empty bucket")
 var from:=Vector3(42.1,42.2,41.75);var to:=Vector3(42.1,41.6,41.75)
 var result:Dictionary=water.transfer_bucket(from,to,false,inventory,0,inventory.snapshot().revision)
 check(not result.ok and water.statistics().water_ml==62500 and inventory.snapshot().slots[0].water_ml==0,"Insufficient shoreline source cannot partially fill bucket")
 var held:PackedByteArray=water.capture_snapshot(catalog);var items:Dictionary=inventory.snapshot()
 check(not water.transfer_bucket(from,to,false,inventory,0,-1).ok and water.capture_snapshot(catalog)==held and inventory.snapshot()==items,"stale shoreline transfer preserves water and inventory exactly")
 result=water.transfer_bucket(from,to,true,inventory,0,inventory.snapshot().revision)
 check(not result.ok and water.statistics().water_ml==62500 and inventory.snapshot().slots[0].water_ml==0,"Empty bucket cannot pour at shoreline")
 held=water.capture_snapshot(catalog);items=inventory.snapshot()
 result=water.transfer_bucket(Vector3(42.4,42.2,41.75),Vector3(42.4,41.6,41.75),false,inventory,0,items.revision)
 check(not result.ok and water.capture_snapshot(catalog)==held and inventory.snapshot()==items,"solid side of clipped shoreline cannot scoop neighbouring water")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file=FileAccess.open("res://reports/water_shore_clipping.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"area":area,"shore_triangles":mesh.faces.shore_triangles}));file.close()
 print("WATER_SHORE_CLIPPING failures=",failures);quit(failures)
