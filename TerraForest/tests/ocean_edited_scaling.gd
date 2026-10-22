# SPDX-License-Identifier: 0BSD
# Residency-policy probe only: deliberately no terrain sampling or rendering.
# Invalidation marks authoritative edited ownership through the production API.
# Exit 1 denotes a real scalability failure, not an accepted performance baseline.
extends SceneTree
func _initialize()->void:
 var water=ClassDB.instantiate("NativeRegionalWater")
 var rows:Array=[];var failed:=false
 var pristine=ClassDB.instantiate("NativeRegionalWater")
 for stop in 80:
  var point:=Vector3(50,40,40+stop*24) if stop<40 else Vector3(1950,40,40+(stop-40)*24)
  for step in 44:pristine.update_ocean_residency(point,32)
  for step in 40:pristine.update_ocean_residency(Vector3(1000,40,1000),32)
  if pristine.statistics().regions!=0 or pristine.statistics().capacity_reached:
   print("INVALID_FIXTURE pristine control failed");quit(2);return
 for stop in 80:
  var point:=Vector3(50,40,40+stop*24) if stop<40 else Vector3(1950,40,40+(stop-40)*24)
  for step in 44:water.update_ocean_residency(point,32)
  var coordinate:=Vector3(floorf(point.x/4)*4,36,floorf(point.z/4)*4)
  water.invalidate(AABB(coordinate+Vector3.ONE*0.1,Vector3.ONE*0.2),true)
  for step in 40:water.update_ocean_residency(Vector3(1000,40,1000),32)
  var stats:Dictionary=water.statistics()
  rows.append({"stop":stop+1,"regions":stats.regions,"edited":stats.ocean_edited_regions,"bytes":stats.resident_cell_bytes,"capacity":stats.capacity_reached})
  if stats.regions>1200 or stats.capacity_reached:failed=true
  if stats.capacity_reached:break
 var report:={"scope":"Native residency policy, no terrain sampling or rendering; one tiny invalidation per separated coast site","pristine_control_regions":pristine.statistics().regions,"resident_budget":1200,"bounded":not failed,"sites":rows}
 var file:=FileAccess.open("res://reports/ocean_edited_scaling.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
 print("OCEAN_EDITED_SCALING ",JSON.stringify(report))
 quit(1 if failed else 0)
