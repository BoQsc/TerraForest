# SPDX-License-Identifier: 0BSD
extends SceneTree
class Backend extends RefCounted:
 var world_generator:=38
class Terrain extends Node3D:
 var backend:=Backend.new()
var failures:=0
func check(ok:bool,label:String)->void:
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var factory=ClassDB.instantiate("NativeWaterMapIdentity")
 var water=ClassDB.instantiate("NativeRegionalWater")
 var catalog=ClassDB.instantiate("NativeLakeCatalog")
 var packet:PackedByteArray=water.capture_snapshot(catalog.encode([],1))
 var worker:=Thread.new();worker.start(factory.prepare.bind(packet))
 while worker.is_alive():await process_frame
 var prepared:RefCounted=worker.wait_to_finish()
 check(prepared!=null and prepared.get_bytes()==packet,"worker prepares exact immutable water packet")
 var copy:PackedByteArray=prepared.get_bytes();copy[0]^=1
 check(prepared.get_bytes()==packet,"caller mutation cannot change prepared bytes")
 check(water.restore_prepared(prepared) and water.statistics().map_identity_scene_hash_us==0,"prepared restore hashes no bytes on scene thread")
 check(prepared.get_catalog()==catalog.encode([],1),"prepared catalog matches validated packet")
 check(not water.restore_prepared(prepared),"prepared state cannot be consumed twice")
 var retire_worker:=Thread.new();retire_worker.start(prepared.retire)
 while retire_worker.is_alive():await process_frame
 retire_worker.wait_to_finish()
 check(not water.restore_prepared(prepared),"retired handoff cannot install discarded state")
 var identity:String=water.survey_cache_identity()
 check(not identity.is_empty() and water.restore_snapshot(packet) and water.survey_cache_identity()==identity,"prepared and ordinary restore certify identical content")
 var bad= factory.prepare(PackedByteArray([1,2,3]))
 check(not water.restore_prepared(bad) and water.survey_cache_identity()==identity,"invalid prepared payload cannot replace certified state")
 check(not water.restore_prepared(null),"missing prepared payload rejected")
 var revision:int=water.survey_revision_id()
 check(water.capture_snapshot(catalog.encode([],1))==packet and water.survey_revision_id()==revision and water.survey_cache_identity()==identity,"serialization preserves the unchanged logical map stamp and certificate")
 var frozen=water.capture_storage_snapshot(catalog.encode([],1))
 var saved:PackedByteArray=frozen.serialize_snapshot() if frozen is RefCounted else frozen
 check(saved==packet and water.survey_revision_id()==revision and water.survey_cache_identity()==identity,"storage capture does not turn persistence into a water edit")
 var terrain:=Terrain.new()
 var lakes=load("res://addons/volumetric_water/lake_world.gd").new()
 lakes.terrain=terrain
 check(lakes.prepare() and lakes.restore_snapshot(packet),"ordinary island lake bridge restores certified state")
 var restored_identity:String=lakes.water.survey_cache_identity()
 lakes.water.set_western_ocean(false);lakes.water.set_surrounding_ocean(true)
 check(not restored_identity.is_empty() and lakes.water.survey_cache_identity()==restored_identity,"first island ocean configuration preserves restored map certificate")
 lakes.water.set_surrounding_ocean(false)
 check(lakes.water.survey_cache_identity().is_empty(),"actual ocean configuration change invalidates certified water map")
 var fixture:PackedByteArray=region_fixture(125000)
 var resident=ClassDB.instantiate("NativeRegionalWater")
 check(resident.restore_snapshot(fixture),"resident water locality fixture restores")
 var pending:Dictionary={}
 var until:=Time.get_ticks_msec()+5000
 while Time.get_ticks_msec()<until:
  pending=resident.next_mesh_batch()
  if pending.get("complete",false):break
  await process_frame
 var water_revision:int=resident.survey_revision_id()
 var certificate:String=resident.survey_cache_identity()
 check(pending.get("complete",false),"water render batch prepared before unrelated building edit")
 check(not resident.invalidate_buildings(AABB(Vector3(1000,20,1000),Vector3(4,4,4))) and resident.survey_revision_id()==water_revision and resident.survey_cache_identity()==certificate,"dry building edit preserves water revision and identity")
 check(pending.get("complete",false) and resident.commit_mesh_batch(pending.batch),"unrelated building edit preserves pending native mesh publication")
 check(resident.invalidate_buildings(AABB(Vector3(4,36,1000),Vector3(1,1,1))) and resident.survey_revision_id()!=water_revision,"intersecting building edit still invalidates water contacts")
 var structures:=Node3D.new();root.add_child(structures);lakes.blocks=structures
 lakes._prepared_slice={"test_marker":true};var structure_revision:int=lakes._occupancy_structure_revision
 lakes._building_changed(AABB(Vector3(1000,20,1000),Vector3(4,4,4)))
 check(lakes._prepared_slice.get("test_marker",false) and lakes._occupancy_structure_revision==structure_revision,"bridge retains prepared occupancy across unrelated building edit")
 lakes._prepared_slice={};lakes.blocks=null;structures.free()
 lakes.free();terrain.free()
 print("WATER_MAP_IDENTITY failures=",failures);quit(1 if failures else 0)

func region_fixture(amount:int)->PackedByteArray:
 var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
 var b:=PackedByteArray();b.resize(32+catalog.size()+9076+12);b.fill(0)
 b.encode_u32(0,0x31575256);b.encode_u32(4,13);b.encode_u32(8,catalog.size());b.encode_u32(12,1);b.encode_u64(16,amount);b.encode_u64(24,12)
 for i in catalog.size():b[32+i]=catalog[i]
 var at:=32+catalog.size();b.encode_u64(at,(1<<24)|(9<<12)|250);b.encode_u32(at+8,1);b.encode_u32(at+12,9)
 for i in 512:b.encode_u16(at+16+i*12+2,500)
 b.encode_u64(at+20,amount)
 for i in 729:b.encode_float(at+6160+i*4,1.0)
 return b
