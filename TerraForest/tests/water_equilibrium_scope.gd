# SPDX-License-Identifier: 0BSD
extends "res://tests/water_equilibrium.gd"
func _initialize()->void:run_scope.call_deferred()
func run_scope()->void:
 var cells:Dictionary={}
 for z in 64:
  for x in 64:cells[Vector3i(11+x*24,83,11+z*24)]=[0,500,125000]
 var donor:=Vector3i(11,83,11);var receiver:=donor-Vector3i.UP
 cells[receiver]=[0,500,0]
 var water:=fixture(cells)
 var total:int=water.statistics().water_ml
 water.settle_after_edit(AABB(Vector3(donor)*.5,Vector3.ONE*.5))
 var result:=await solve(water)
 check(result.get("ok",false) and result.get("snapshot_regions",4096)<16,"Local edit snapshots only its affected group with 4,096 resident pools: "+str(result))
 check(water.statistics().water_ml==total,"Scoped equilibrium conserves the entire store quantity")
 check(water.depth_at(Vector3(receiver)*.5+Vector3.ONE*.25)>0,"Local receiver fills in the large resident store")
 check(water.depth_at(Vector3(11+63*24,83,11+63*24)*.5+Vector3.ONE*.25)>0,"Unrelated far pool remains intact")
 print("WATER_EQUILIBRIUM_SCOPE checks=",checks," failures=",failures);quit(failures)
