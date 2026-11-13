# SPDX-License-Identifier: 0BSD
extends "res://tests/water_equilibrium.gd"
func _initialize()->void:run_ocean.call_deferred()
func ocean_fixture(boundary:bool,vacancy:bool=false)->RefCounted:
 var cells:Dictionary={}
 for x in range(7,17):cells[Vector3i(x,79,11)]=[0,500,125000 if x<16 else 0]
 cells[Vector3i(17,79,11)]=[0,500,115000 if vacancy else 125000]
 cells[Vector3i(18,77,11)]=[0,400,10000]
 var initial:=fixture(cells);var bytes:=snapshot(initial)
 # Version 10 adds ocean flags and one empty vacancy table per region.
 var previous_size:=bytes.size();var extra:=4*bytes.decode_u32(12)+(8 if vacancy else 0)
 bytes.resize(previous_size+extra)
 for i in range(previous_size,bytes.size()):bytes[i]=0
 bytes.encode_u64(24,bytes.decode_u64(24)+extra);bytes.encode_u32(4,10)
 if vacancy:
  var last_table:int=previous_size+4*(bytes.decode_u32(12)-1)
  bytes.encode_u32(last_table,1);bytes.encode_u32(last_table+4,1+8*7+64*3);bytes.encode_u32(last_table+8,10000)
 var offset:=32+bytes.decode_u32(8)
 for n in bytes.decode_u32(12):
  var x:int=(bytes.decode_u64(offset)>>24)&4095
  bytes.encode_u32(offset+12,(1 if boundary and x<2 else 2)<<2)
  offset+=9076
 var water:RefCounted=ClassDB.instantiate("NativeRegionalWater")
 check(water.restore_snapshot(bytes),"Ocean boundary fixture restores")
 water.set_surrounding_ocean(true)
 water.settle_after_edit(AABB(Vector3(8.25,39.75,5.75),Vector3.ONE*.1))
 return water
func run_ocean()->void:
 var water:=ocean_fixture(true);var before:int=water.statistics().water_ml
 var result:=await solve(water)
 check(result.get("ok",false) and result.get("ocean_exchange_ml",0)==125000,"Open sea boundary explicitly accounts for crater inflow: "+str(result))
 check(water.statistics().water_ml==before+125000,"Owned water increases only by recorded reservoir inflow")
 check(water.depth_at(Vector3(8.25,39.75,5.75))>.2,"Connected excavated cell fills to sea level")
 check(amounts(water).get(Vector3i(18,77,11),0)==10000,"Sealed underwater pocket neither fills nor loses its finite quantity")
 water=ocean_fixture(false);before=water.statistics().water_ml;result=await solve(water)
 check(result.get("ok",false) and result.get("ocean_exchange_ml",0)==0 and water.statistics().water_ml==before,"Without a pristine sea boundary the edited pool remains finite: "+str(result))
 water=ocean_fixture(true,true)
 check(amounts(water).get(Vector3i(17,79,11),0)==115000,"Saved ocean scoop restores a retained vacancy")
 result=await solve(water)
 check(result.get("ok",false) and amounts(water).get(Vector3i(17,79,11),0)==115000,"First shoreline edit retains the scooped amount")
 water.settle_after_edit(AABB(Vector3(8.25,39.75,5.75),Vector3.ONE*.1))
 result=await solve(water)
 check(result.get("ok",false) and result.get("ocean_exchange_ml",0)==0 and amounts(water).get(Vector3i(17,79,11),0)==115000,"Repeated shoreline edit does not refill a retained vacancy")
 print("WATER_OCEAN_EQUILIBRIUM checks=",checks," failures=",failures);quit(failures)
