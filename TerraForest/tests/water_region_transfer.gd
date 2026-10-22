# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize()->void:
 var water=ClassDB.instantiate("NativeRegionalWater")
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[42,19]))
 water.update_ocean_residency(Vector3(4,40,1000),1)
 var request:Dictionary=water.next_request();var coordinate:Vector3i=request.coordinate
 check(water.capture_region_snapshot(coordinate).is_empty(),"pristine water is not archived as an edit")
 var patch=ClassDB.instantiate("NativeWaterTerrainPatch");patch.configure(coordinate)
 var status:=0
 for step in 200:
  status=patch.sample_terrain(core,256,0,0)
  if status!=0:break
 check(status==1 and water.accept_patch(patch),"actual terrain occupancy prepared")
 check(water.brush(Vector3(6,31.8,1002),1.5,-1000000)>0,"actual sea edited")
 var packet:PackedByteArray=water.capture_region_snapshot(coordinate)
 check(not packet.is_empty() and packet.decode_u32(12)==1,"one edited region exported")
 var copy=ClassDB.instantiate("NativeRegionalWater")
 check(copy.restore_region_snapshot(coordinate,packet,copy.survey_revision_id(),true),"validated region installed")
 check(copy.capture_region_snapshot(coordinate)==packet and copy.statistics().water_ml==water.statistics().water_ml,"exact region and quantity restored")
 var before:PackedByteArray=copy.capture_region_snapshot(coordinate)
 check(not copy.restore_region_snapshot(coordinate,packet,copy.survey_revision_id(),true) and copy.capture_region_snapshot(coordinate)==before,"duplicate cannot overwrite or duplicate quantity")
 var empty=ClassDB.instantiate("NativeRegionalWater")
 check(not empty.restore_region_snapshot(coordinate,packet,empty.survey_revision_id()+1,true),"stale completion rejected")
 check(not empty.restore_region_snapshot(coordinate+Vector3i(1,0,0),packet,empty.survey_revision_id(),true),"wrong region rejected")
 check(not empty.restore_region_snapshot(coordinate,packet.slice(0,packet.size()-1),empty.survey_revision_id(),true),"truncated packet rejected")
 var broken:=packet.duplicate();broken.encode_u64(16,packet.decode_u64(16)+1)
 check(not empty.restore_region_snapshot(coordinate,broken,empty.survey_revision_id(),true) and empty.statistics().regions==0,"invalid quantity fails atomically")
 check(empty.restore_region_snapshot(coordinate,packet,empty.survey_revision_id(),false) and empty.statistics().pending_regions==1,"untrusted occupancy requests terrain resampling")
 check(empty.statistics().water_ml==water.statistics().water_ml,"resampling request preserves authoritative quantity")
 # Add a valid vacancy entry to exercise this independent authoritative channel.
 var vacant:=packet.duplicate();vacant.resize(packet.size()+8)
 vacant.encode_u64(24,packet.decode_u64(24)+8);vacant.encode_u32(packet.size()-4,1)
 vacant.encode_u32(packet.size(),0);vacant.encode_u32(packet.size()+4,1234)
 var vacancy_copy=ClassDB.instantiate("NativeRegionalWater")
 check(vacancy_copy.restore_region_snapshot(coordinate,vacant,0,true) and vacancy_copy.capture_region_snapshot(coordinate)==vacant,"vacancies survive exact region transfer")
 water.remove_bounds(AABB(Vector3(coordinate)*4,Vector3(4,4,4)))
 var dry:PackedByteArray=water.capture_region_snapshot(coordinate)
 var dry_copy=ClassDB.instantiate("NativeRegionalWater")
 check(not dry.is_empty() and dry_copy.restore_region_snapshot(coordinate,dry,0,true),"empty edited override is transferable")
 check(dry_copy.statistics().water_ml==0 and dry_copy.statistics().ocean_edited_regions==1 and dry_copy.capture_region_snapshot(coordinate)==dry,"empty override retains ownership and exact record")
 check(water.capture_region_snapshot(Vector3i(-1,0,0)).is_empty(),"invalid coordinate rejected")
 print("WATER_REGION_TRANSFER failures=",failures);quit(1 if failures else 0)
