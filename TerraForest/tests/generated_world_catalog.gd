# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 var backend=preload("res://addons/volumetric_terrain/terrain_backend.gd").new()
 backend.native=ClassDB.instantiate("TerrainCore")
 backend.world_generator=4
 var water=ClassDB.instantiate("NativeRegionalWater")
 backend.snapshot_validators["volumetric_water"]=water
 backend.native.execute(backend.Codec.command(6,[1703,4]))
 check(backend._initialize_generated_components(),"new generated world creates addon definitions")
 var data:PackedByteArray=backend.components.get("volumetric_water",PackedByteArray())
 check(water.validate_snapshot(data),"current regional validator accepts generated catalog")
 var catalog=ClassDB.instantiate("NativeLakeCatalog")
 var decoded:Dictionary=catalog.decode(water.snapshot_catalog(data))
 check(decoded.get("ok",false) and decoded.get("records",[]).size()==4 and decoded.get("next_id",0)==5,"four generated definitions retain identities")
 var lakes=preload("res://addons/volumetric_water/lake_world.gd").new()
 lakes.prepare()
 check(lakes.restore_snapshot(data),"main-world adapter restores new-world definitions")
 var dirty:bool=lakes._lakes.size()==4
 for item:Dictionary in lakes._lakes.values():dirty=dirty and item.dirty
 check(dirty,"new lakes await generation rather than masquerading as empty cached water")
 lakes.free()
 backend.world_generator=1
 check(backend._initialize_generated_components() and backend.components.is_empty(),"original generator keeps no generated lakes")
 backend.native=null
 print("GENERATED_WORLD_CATALOG failures=",failures)
 quit(1 if failures else 0)
