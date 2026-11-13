# SPDX-License-Identifier: 0BSD
extends "res://tests/water_blast_settling.gd"
func _initialize()->void:run_equilibrium.call_deferred()
func solve(water:RefCounted)->Dictionary:
 var job:RefCounted=water.begin_equilibrium()
 if job==null:return {"ok":false,"reason":"No equilibrium job"}
 var task:=WorkerThreadPool.add_task(job.prepare,false,"Equilibrium regression")
 while not WorkerThreadPool.is_task_completed(task):await process_frame
 WorkerThreadPool.wait_for_task_completion(task)
 return water.finish_equilibrium(job)
func run_equilibrium()->void:
 var high:=Vector3i(83,83,83);var low:=high+Vector3i.DOWN
 # Old full coastal cells could round up by one ml without a pending flag.
 var legacy_surplus:=fixture({high:[0,500,125001],low:[0,500,0]})
 check(legacy_surplus.statistics().settling_regions>0,"Restored over-capacity quantity is scheduled without an edit")
 var repaired:Dictionary=await solve(legacy_surplus)
 check(repaired.get("ok",false) and legacy_surplus.statistics().water_ml==125001 and amounts(legacy_surplus)=={low:125000,high:1},"Legacy rounding surplus settles without deleting water: "+str(repaired))
 var separate:=fixture({high:[0,500,12500],high+Vector3i.RIGHT:[250,500,0],high+Vector3i(8,8,0):[0,500,12500]})
 separate.settle_after_edit(AABB(Vector3(high)*.5,Vector3(5,5,1)))
 var separate_result:Dictionary=await solve(separate)
 check(separate_result.get("ok",false) and separate_result.get("cells",0)==2,"Disconnected high body does not inflate a lower body's discovery head: "+str(separate_result))
 var water:=fixture({high:[0,500,125000],low:[0,500,0]})
 check(water.begin_equilibrium()==null,"Idle water submits no equilibrium worker")
 water.settle_after_edit(AABB(Vector3(low)*.5,Vector3.ONE*.5))
 var result:=await solve(water)
 check(result.ok and amounts(water)=={low:125000},"One worker transaction fills excavated space with exact conserved quantity: "+str(result))
 check(water.begin_equilibrium()==null and water.statistics().settling_regions==0,"Committed equilibrium returns to zero solver work")
 var row:Dictionary={}
 for x in range(80,88):row[Vector3i(x,83,83)]=[0,500,125000 if x==83 else 1]
 row[Vector3i(79,83,83)]=[500,500,0];row[Vector3i(88,83,83)]=[500,500,0]
 water=fixture(row);water.settle_after_edit(AABB(Vector3(40,41.5,41.5),Vector3(4,.5,.5)))
 result=await solve(water)
 var minimum:=125007;var maximum:=0;var total:=0
 for value:int in amounts(water).values():minimum=mini(minimum,value);maximum=maxi(maximum,value);total+=value
 check(result.ok and total==125007 and maximum-minimum<=1,"One transaction levels a connected layer without pairwise diffusion: "+str(result))
 var saved:=snapshot(water);var reopened:RefCounted=ClassDB.instantiate("NativeRegionalWater")
 check(reopened.restore_snapshot(saved) and amounts(reopened)==amounts(water),"Equilibrated quantities survive existing snapshot format")
 water.settle_after_edit(AABB(Vector3(40,41.5,41.5),Vector3(4,.5,.5)))
 var job:RefCounted=water.begin_equilibrium()
 if job==null:check(false,"Pending equilibrium creates a worker");quit(failures);return
 job.prepare()
 water.brush(Vector3(41.75,41.6,41.75),0,1000)
 result=water.finish_equilibrium(job)
 check(not result.ok and result.get("stale",false) and water.statistics().water_ml==126007,"Concurrent edits reject a stale equilibrium result without overwriting water")
 var left:=Vector3i(82,83,83);var sill:=left+Vector3i.RIGHT;var right:=sill+Vector3i.RIGHT
 water=fixture({left:[0,500,75000],sill:[300,500,1],right:[0,500,1000]})
 water.settle_after_edit(AABB(Vector3(sill)*.5,Vector3.ONE*.5));result=await solve(water)
 var retained:=amounts(water)
 check(result.ok and absi(int(retained.get(left,0))-75000)<=1 and water.statistics().water_ml==76001,"Dry sill retains its upstream pocket while conserving a sub-render remainder: "+str(result))
 water=fixture({left:[0,500,100000],sill:[300,500,0],right:[0,500,0]})
 water.settle_after_edit(AABB(Vector3(sill)*.5,Vector3.ONE*.5));result=await solve(water)
 retained=amounts(water)
 check(result.ok and absi(int(retained.get(left,0))-75000)<=1 and absi(int(retained.get(right,0))-25000)<=1 and water.statistics().water_ml==100000,"Only water above the sill spills into the lower basin: "+str(result))
 water=fixture({high:[0,500,125000],low:[0,200,0]})
 water.settle_after_edit(AABB(Vector3(low)*.5,Vector3.ONE*.5));result=await solve(water)
 check(result.ok and amounts(water)=={high:125000},"A sealed ceiling prevents water reaching the cavity below: "+str(result))
 water=fixture({low:[500,500,125000],high:[0,500,0]})
 water.settle_after_edit(AABB(Vector3(low)*.5,Vector3.ONE*.5));result=await solve(water)
 check(result.ok and amounts(water)=={high:125000},"Solid deposition displaces water into adjacent available space: "+str(result))
 water=fixture({low:[500,500,125000],high:[100,500,0]})
 water.settle_after_edit(AABB(Vector3(low)*.5,Vector3.ONE*.5));result=await solve(water)
 check(result.ok and result.get("blocked_ml",0)==125000 and amounts(water)=={low:125000},"Blocked displacement is retained explicitly without leaking through solid: "+str(result))
 saved=snapshot(water);reopened=ClassDB.instantiate("NativeRegionalWater")
 check(reopened.restore_snapshot(saved) and amounts(reopened)==amounts(water),"Blocked displaced quantity survives save/reload")
 water=fixture({high:[0,500,125000],low:[0,500,0]})
 water.settle_after_edit(AABB(Vector3(low)*.5,Vector3.ONE*.5))
 saved=snapshot(water);reopened=ClassDB.instantiate("NativeRegionalWater")
 check(saved.decode_u32(4) in [11,12] and reopened.restore_snapshot(saved) and reopened.statistics().settling_regions>0,"Interrupted equilibrium retains pending work in a versioned snapshot")
 result=await solve(reopened)
 check(result.ok and amounts(reopened)=={low:125000},"Reload resumes the same finite-volume equilibrium")
 job=water.begin_equilibrium();job.cancel();job.prepare();result=water.finish_equilibrium(job)
 check(result.get("stale",false) and amounts(water)=={high:125000},"Cancelled equilibrium never mutates authoritative quantities")
 var edge:=Vector3i(87,83,83)
 water=fixture({edge:[0,500,125000]});water.settle_after_edit(AABB(Vector3(edge)*.5,Vector3.ONE*.5))
 result=await solve(water)
 check(result.get("pending",false) and result.get("required_regions",0)>0 and amounts(water)=={edge:125000},"Unknown neighboring terrain requests occupancy and retains all water")
 check(water.begin_equilibrium()==null,"Unknown dry frontier blocks redundant workers until terrain arrives")
 water=fixture({high:[500,500,125000],low:[0,200,0]})
 water.settle_after_edit(AABB(Vector3(high)*.5,Vector3.ONE*.5));result=await solve(water)
 check(result.ok and result.get("blocked_ml",0)==125000 and amounts(water)=={high:125000},"Displacement cannot cross the sealed ceiling below a deposited solid")
 water=fixture({left:[300,500,12500],sill:[400,500,1],right:[0,500,0]})
 water.settle_after_edit(AABB(Vector3(sill)*.5,Vector3.ONE*.5));result=await solve(water)
 check(result.ok and int(amounts(water).get(left,0)) in [12500,12501] and water.statistics().water_ml==12501,"A perched pocket cannot teleport across a higher sill into the only lower wet component: "+str(result))
 row={}
 for x in range(83,91):row[Vector3i(x,83,83)]=[0,500,125000 if x==90 else 1 if x==83 else 0]
 water=fixture(row);water.settle_after_edit(AABB(Vector3(41.5,41.5,41.5),Vector3.ONE*.1));result=await solve(water)
 minimum=125001;maximum=0
 for value:int in amounts(water).values():minimum=mini(minimum,value);maximum=maxi(maximum,value)
 check(result.ok and maximum-minimum<=1 and water.statistics().water_ml==125001,"Head discovery includes a higher connected source outside the edited region: "+str(result))
 var upper_sill:=right+Vector3i.RIGHT;var far_pool:=upper_sill+Vector3i.RIGHT
 water=fixture({left:[0,500,125000],sill:[200,500,0],right:[0,500,0],upper_sill:[400,500,0],far_pool:[0,500,0]})
 water.settle_after_edit(AABB(Vector3(left)*.5,Vector3.ONE*.5));result=await solve(water)
 retained=amounts(water)
 check(result.ok and absi(int(retained.get(left,0))-58333)<=1 and absi(int(retained.get(right,0))-58333)<=1 and absi(int(retained.get(sill,0))-8333)<=1 and not retained.has(far_pool) and not retained.has(upper_sill) and water.statistics().water_ml==125000,"Overflow levels the lower merged basins without crossing a second higher sill: "+str(result))
 print("WATER_EQUILIBRIUM checks=",checks," failures=",failures)
 quit(failures)
