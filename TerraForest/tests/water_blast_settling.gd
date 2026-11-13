# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func fixture(cells:Dictionary)->RefCounted:
	var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([])
	var keys:Array[Vector3i]=[]
	for p:Vector3i in cells:
		var k:=Vector3i(p.x/8,p.y/8,p.z/8)
		if k not in keys:keys.append(k)
	keys.sort_custom(func(a:Vector3i,b:Vector3i)->bool:return code(a)<code(b))
	var data:=PackedByteArray();data.resize(32+catalog.size()+keys.size()*(16+512*12));data.fill(0)
	data.encode_u32(0,0x31575256);data.encode_u32(4,1);data.encode_u32(8,catalog.size());data.encode_u32(12,keys.size())
	for i in catalog.size():data[32+i]=catalog[i]
	var total:=0;var offset:=32+catalog.size()
	for k:Vector3i in keys:
		data.encode_u64(offset,code(k));data.encode_u32(offset+8,1);offset+=16
		for i in 512:
			var p:=k*8+Vector3i(i%8,(i/8)%8,i/64)
			var entry:Array=cells.get(p,[500,500,0])
			data.encode_u16(offset,entry[0]);data.encode_u16(offset+2,entry[1]);data.encode_u64(offset+4,entry[2]);total+=entry[2];offset+=12
	data.encode_u64(16,total)
	var water:RefCounted=ClassDB.instantiate("NativeRegionalWater")
	check(water.restore_snapshot(data),"legacy finite-volume fixture accepted")
	return water
func code(p:Vector3i)->int:return (p.x<<24)|(p.y<<12)|p.z
func snapshot(water:RefCounted)->PackedByteArray:return water.capture_snapshot(ClassDB.instantiate("NativeLakeCatalog").encode([]))
func amounts(water:RefCounted)->Dictionary:
	var data:=snapshot(water);var result:Dictionary={};var offset:=32+data.decode_u32(8)
	for n in data.decode_u32(12):
		var k:=data.decode_u64(offset);var base:=Vector3i((k>>24)&4095,(k>>12)&4095,k&4095)*8;offset+=16
		for i in 512:
			var amount:=data.decode_u64(offset+4)
			if amount:result[base+Vector3i(i%8,(i/8)%8,i/64)]=amount
			offset+=12
		offset+=729*4
	return result
func settle(water:RefCounted)->void:
	for tick in 3000:
		water.advance_settling(256)
		if water.statistics().settling_regions==0:return
	check(false,"settling reaches idle within bounded fixture work")
func _initialize()->void:
	var high:=Vector3i(83,83,83);var low:=high+Vector3i.DOWN
	var water:=fixture({high:[0,500,125000],low:[0,500,0]})
	water.advance_settling(256)
	check(amounts(water).get(high)==125000 and water.statistics().settling_steps==0,"unchanged static water does no settling work")
	water.settle_after_edit(AABB(Vector3(low)*.5,Vector3.ONE*.5))
	var before:int=water.statistics().settling_steps;water.advance_settling(1)
	check(water.statistics().settling_steps-before<=1,"explicit cell work budget retained")
	var pending:=snapshot(water)
	check(pending.decode_u32(4)==11,"unfinished settling uses versioned pending state")
	var restored:RefCounted=ClassDB.instantiate("NativeRegionalWater")
	check(restored.restore_snapshot(pending) and restored.statistics().settling_regions>0,"save interruption retains pending work")
	var archived:=pending.duplicate();var region_offset:=32+archived.decode_u32(8)
	archived.encode_u32(region_offset+12,archived.decode_u32(region_offset+12)|8)
	var paged:RefCounted=ClassDB.instantiate("NativeRegionalWater")
	check(paged.restore_snapshot(archived),"edited ocean region with pending settling restores")
	var coordinate:=Vector3i(high.x/8,high.y/8,high.z/8)
	var packet:PackedByteArray=paged.capture_region_snapshot(coordinate)
	var recipient:RefCounted=ClassDB.instantiate("NativeRegionalWater")
	check(recipient.restore_region_snapshot(coordinate,packet,0,true) and recipient.statistics().settling_regions>0,"region paging retains pending settling")
	settle(recipient)
	check(amounts(recipient)=={low:125000},"paged settling keeps exact owned water")
	settle(water);settle(restored)
	check(amounts(water)=={low:125000} and amounts(restored)==amounts(water),"unsupported water falls without duplication across save/reload")
	check(water.statistics().water_ml==125000,"gravity preserves exact total millilitres")
	before=water.statistics().settling_steps;water.advance_settling(256)
	check(water.statistics().settling_steps==before,"settled water returns to zero work")
	water=fixture({high:[0,500,125000],low:[0,200,0]})
	water.settle_after_edit(AABB(Vector3(low)*.5,Vector3.ONE*.5));settle(water)
	check(amounts(water)=={high:125000},"a solid ceiling blocks vertical transfer into an underlying cave")
	var side:=low+Vector3i.RIGHT
	water=fixture({low:[100,500,100000],side:[100,500,0]})
	water.settle_after_edit(AABB(Vector3(side)*.5,Vector3.ONE*.5));settle(water)
	check(amounts(water)=={low:50000,side:50000},"water fills a connected side crater with conserved volume")
	water=fixture({low:[300,500,50000],side:[0,500,0]})
	water.settle_after_edit(AABB(Vector3(side)*.5,Vector3.ONE*.5));settle(water)
	check(amounts(water).get(side,0)>=49999 and water.statistics().water_ml==50000,"water spills over an opening into a deeper dry crater")
	water=fixture({low:[300,500,50000],side:[0,200,0]})
	water.settle_after_edit(AABB(Vector3(side)*.5,Vector3.ONE*.5));settle(water)
	check(amounts(water)=={low:50000},"disconnected air intervals cannot drain through solid terrain")
	high=Vector3i(83,80,83);low=high+Vector3i.DOWN
	water=fixture({high:[0,500,125000],low:[0,500,0]})
	water.settle_after_edit(AABB(Vector3(low)*.5,Vector3.ONE*.5));settle(water)
	check(amounts(water)=={low:125000},"settling crosses a resident region seam")
	water=fixture({low:[500,500,125000],high:[0,500,0]})
	water.settle_after_edit(AABB(Vector3(low)*.5,Vector3.ONE*.5));settle(water)
	check(amounts(water)=={high:125000},"fully displaced water reaches adjacent open space without deletion")
	water=fixture({low:[500,500,125000],high:[100,500,0]})
	water.settle_after_edit(AABB(Vector3(low)*.5,Vector3.ONE*.5));settle(water)
	check(amounts(water)=={low:125000},"blocked displaced water is retained rather than crossing a solid receiver floor")
	var blocked:=snapshot(water)
	var blocked_restore:RefCounted=ClassDB.instantiate("NativeRegionalWater")
	check(blocked_restore.restore_snapshot(blocked) and amounts(blocked_restore)=={low:125000},"blocked displacement survives save and reload exactly")
	water=fixture({low:[0,500,150000],high:[0,500,0]})
	water.settle_after_edit(AABB(Vector3(low)*.5,Vector3.ONE*.5));settle(water)
	check(amounts(water)=={low:125000,high:25000},"capacity excess rises into adjacent space while preserving the filled donor")
	var row:Dictionary={}
	for x in range(80,88):row[Vector3i(x,83,83)]=[0,500,125000 if x==83 else 1]
	water=fixture(row)
	water.settle_after_edit(AABB(Vector3(40,41.5,41.5),Vector3(4,.5,.5)));settle(water)
	var row_amounts:=amounts(water);var minimum:=125000;var maximum:=0;var row_total:=0
	for value:int in row_amounts.values():minimum=mini(minimum,value);maximum=maxi(maximum,value);row_total+=value
	check(row_amounts.size()==8 and maximum-minimum<=3 and row_total==125007,"Connected layer equilibrates within declared head precision without losing integer remainders")
	var left:=Vector3i(82,83,83);var sill:=left+Vector3i.RIGHT;var right:=sill+Vector3i.RIGHT
	water=fixture({left:[0,500,75000],sill:[300,500,1],right:[0,500,1000]})
	water.settle_after_edit(AABB(Vector3(sill)*.5,Vector3.ONE*.5));settle(water)
	check(amounts(water).get(left,0)==75000 and water.statistics().water_ml==76001,"Layer acceleration cannot drain a retained pocket across a dry sill")
	# Native-only derived fixtures do not execute this coordinator check.
	var lake=load("res://addons/volumetric_water/lake_world.gd").new()
	lake.water=fixture({high:[0,500,125000],low:[0,500,0]})
	lake.settling_enabled=func()->bool:return false
	lake._settle_committed_edit(AABB(Vector3(low)*.5,Vector3.ONE*.5),1)
	check(lake.water.statistics().settling_regions==0,"unqualified water flow stays disabled by default")
	lake.settling_enabled=func()->bool:return true
	lake.settling_active=func()->bool:return false
	lake._settle_committed_edit(AABB(Vector3(low)*.5,Vector3.ONE*.5),2)
	check(lake.water.statistics().settling_regions>0 and amounts(lake.water)=={high:125000},"committed mining/blast edit queues conserved water even while paused")
	settle(lake.water)
	check(amounts(lake.water)=={low:125000},"shared terrain publication wake settles into newly opened space")
	lake.free()
	print("WATER_BLAST_SETTLING checks=",checks," failures=",failures)
	quit(1 if failures else 0)
