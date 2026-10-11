# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize():
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 var failures:=0
 for name in ["NativeLakeVolume","NativeWaterQuantity","NativeWaterCapacity","NativeWaterSettling","NativeWaterTopology","NativeWaterBasins","NativeWaterProfiles","NativeWaterField","NativeWaterRegions","NativeWaterNetwork","NativeWaterSurface","NativeWaterScene","NativeWaterRuntime","NativeWaterRemapPlan"]:
  if ClassDB.class_exists(name):
   push_error("Removed implementation still registered: "+name);failures+=1
 var water=ClassDB.instantiate("NativeRegionalWater")
 var catalog=ClassDB.instantiate("NativeLakeCatalog")
 var bytes:PackedByteArray=water.capture_snapshot(catalog.encode([]))
 if not water.validate_snapshot(bytes) or not water.restore_snapshot(bytes):failures+=1
 # Old empty catalog bytes remain readable as data, without an old simulator.
 var legacy:=PackedByteArray();legacy.resize(20);legacy.fill(0)
 legacy.encode_u32(0,0x314c5754);legacy.encode_u32(4,1);legacy.encode_u64(12,1)
 if not catalog.decode(legacy).ok or not water.validate_snapshot(legacy):failures+=1
 print("WATER_SINGLE_RUNTIME failures=",failures)
 DirAccess.make_dir_recursive_absolute("res://reports")
 var report=FileAccess.open("res://reports/water_single_runtime.json",FileAccess.WRITE)
 report.store_string(JSON.stringify({"failures":failures}));report.close()
 quit(failures)
