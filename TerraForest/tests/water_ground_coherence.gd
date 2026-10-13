# SPDX-License-Identifier: 0BSD
extends SceneTree
const Probe=preload("res://tests/water_coherence_probe.gd")
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 var folder:="res://tests/fixtures/water_ground_coherence/"
 var context:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(folder+"context.json"))
 var target:=Vector3(context.target[0],context.target[1],context.target[2])
 var bytes:PackedByteArray=FileAccess.get_file_as_bytes(folder+"initial_cached.bin.gz").decompress_dynamic(4194304,FileAccess.COMPRESSION_GZIP)
 var water=ClassDB.instantiate("NativeRegionalWater")
 if not water.restore_snapshot(bytes):push_error("Captured fixture failed to restore");quit(2);return
 var total:int=water.statistics().water_ml
 for frame in 120:water.advance(2048,1.0/60.0)
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 bytes=water.capture_snapshot(catalog)
 var rows:Array=[]
 for r in bytes.decode_u32(12):
  var base:int=32+bytes.decode_u32(8)+r*9076;var key:int=bytes.decode_u64(base)
  var region:=Vector3i((key>>24)&4095,(key>>12)&4095,key&4095)
  for i in 512:
   var ml:int=bytes.decode_u64(base+20+i*12)&0x7fffffffffffffff
   if ml==0:continue
   var cell:Vector3i=region*8+Vector3i(i%8,(i/8)%8,i/64)
   var center:=Vector3(cell)*0.5+Vector3.ONE*0.25
   if center.distance_to(target)>3:continue
   rows.append({"cell":[cell.x,cell.y,cell.z],"ml":ml,"distance_m":center.distance_to(target),"geometry":water.cell_geometry(center)})
 var groups:Dictionary=Probe.components(water,rows)
 var conserved:bool=water.statistics().water_ml==total
 var coherent:bool=groups.components.size()==1
 var failures:int=int(not conserved)+int(not coherent)
 print("PASS " if conserved else "FAIL ","Captured-world replay preserves every millilitre")
 print("PASS " if coherent else "FAIL ","Gentle-ground bucket pour has one connected local water body")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var out:=FileAccess.open("res://reports/water_ground_coherence.json",FileAccess.WRITE)
 out.store_string(JSON.stringify({"failures":failures,"components":groups,"statistics":water.statistics(),"conserved":conserved},"  "));out.close()
 print("WATER_GROUND_COHERENCE failures=",failures);quit(failures)
