# SPDX-License-Identifier: 0BSD
extends "res://tests/water_blast_settling.gd"
func _initialize()->void:run_equilibrium.call_deferred()
func solve(water:RefCounted,local_response:bool=false)->Dictionary:
 var job:RefCounted=water.begin_equilibrium(0,local_response)
 if job==null:return {"ok":false,"reason":"No equilibrium job"}
 var task:=WorkerThreadPool.add_task(job.prepare,false,"Equilibrium regression")
 while not WorkerThreadPool.is_task_completed(task):await process_frame
 WorkerThreadPool.wait_for_task_completion(task)
 return water.finish_equilibrium(job)

func check_regional_prisms()->void:
 var cells:Dictionary={}
 for z in range(81,167):
  for x in range(81,175):
   cells[Vector3i(x,83,z)]=[0,500,60000 if x%2 else 65000]
 var water:=fixture(cells)
 water.settle_after_edit(AABB(Vector3(36,35,36),Vector3(56,20,52)))
 var result:=await solve(water,true)
 var stored:=amounts(water)
 var uniform:=stored.size()==cells.size()
 for amount:int in stored.values():uniform=uniform and amount==62500
 check(result.ok and result.get("prism_nodes",0)==132 and not result.has("prism_fallback") and uniform,
  "132 connected region prisms agree with the analytical water head in every cell: "+str(result))

func check_level_section()->void:
 var cells:Dictionary={}
 for z in range(9,12):
  for y in range(9,12):
   for x in range(9,12):cells[Vector3i(x,y,z)*8]=[500,500,0]
 for z in range(80,88):
  for x in range(80,88):cells[Vector3i(x,83,z)]=[0,500,62500]
 cells[Vector3i(83,83,83)]=[500,500,0]
 var water:=fixture(cells)
 var sections:=0
 for step in 64:
  var packet:Dictionary=water.next_mesh_batch(false,true)
  if packet.is_empty():break
  if packet.get("coordinate")==Vector3i(10,10,10) and packet.faces.get("level_section",false):sections+=1
  if packet.complete:water.commit_mesh_batch(packet.batch)
 var contact:=true
 for offset:Vector2 in [Vector2(-.27,0),Vector2(.27,0),Vector2(0,-.27),Vector2(0,.27),Vector2.ZERO]:
  var start:=Vector3(41.75+offset.x,42.0,41.75+offset.y)
  var hit:Dictionary=water.raycast_surface(start,start-Vector3.UP)
  if offset==Vector2.ZERO:contact=contact and not hit.hit
  else:contact=contact and hit.hit and absf(hit.get("point",Vector3.ZERO).y-41.75)<.00001 and water.depth_at(start-Vector3.UP*.26)>0
 check(sections==1 and contact,"A level volume reaches all four sides of an obstacle within 2 cm and leaves its solid interior dry")

func check_open_sheet()->void:
 var cells:Dictionary={}
 for z in range(9,12):
  for y in range(9,12):
   for x in range(9,13):cells[Vector3i(x,y,z)*8]=[500,500,0]
 for z in range(77,91):
  for x in range(77,99):
   cells[Vector3i(x,82,z)]=[0,500,125000]
   cells[Vector3i(x,83,z)]=[0,500,54000+1800*maxi(0,x-85)+int((x+z)%2)]
   cells[Vector3i(x,84,z)]=[0,500,0]
 var stores:Array=[]
 var open_owners:=0
 for indexed:bool in [false,true]:
  var water:=fixture(cells)
  for step in 256:
   var packet:Dictionary=water.next_mesh_batch(false,indexed)
   if packet.is_empty():break
   if packet.has("coordinate") and packet.faces.get("open_sheet",false):open_owners+=1
   if packet.complete:water.commit_mesh_batch(packet.batch)
  stores.append(water)
 var matching:=true
 for iz in 15:
  for ix in 34:
   var point:=Vector3(40.05+ix*.232,42.3,40.06+iz*.257)
   var a:Dictionary=stores[0].raycast_surface(point,point-Vector3.UP)
   var b:Dictionary=stores[1].raycast_surface(point,point-Vector3.UP)
   matching=matching and a.hit and b.hit and absf(a.get("point",Vector3.ZERO).y-b.get("point",Vector3.ZERO).y)<.00002
   if a.hit and b.hit:
    matching=matching and stores[1].depth_at(b.point-Vector3.UP*.001)>0 and stores[1].depth_at(b.point+Vector3.UP*.001)==0
 check(open_owners>=2 and matching,"Two open lake tiles share the clipped reference head, immersion and seam for both a one-millilitre step and a graded surface")

func check_inclined_faces()->void:
 var cells:Dictionary={}
 for z in range(81,86):
  for x in range(83,92):
   cells[Vector3i(x,82,z)]=[0,500,0]
   cells[Vector3i(x,83,z)]=[0,500,125000 if x>=88 else 30000+14000*(x-83)]
   cells[Vector3i(x,84,z)]=[0,500,12000*(x-87) if x>=88 else 0]
 # Leave a hole through both tiers and a dry opening below the suspended sheet.
 for y in range(83,85):cells[Vector3i(87,y,83)]=[500,500,0]
 var stores:Array[RefCounted]=[]
 var optimized:=0
 for indexed:bool in [false,true]:
  var water:=fixture(cells)
  for step in 128:
   var packet:Dictionary=water.next_mesh_batch(false,indexed)
   if packet.is_empty():break
   if packet.has("coordinate") and indexed:optimized+=int(packet.faces.get("monotone_cells",0))
   if packet.complete:water.commit_mesh_batch(packet.batch)
  stores.append(water)
 var agreeing:=true
 var hits:=0
 var rays:Array=[]
 for iz in 15:
  for ix in 29:
   var p:=Vector3(41.57+.147*ix,42.9,40.57+.143*iz)
   rays.append([p,p-Vector3.UP*2]);rays.append([p-Vector3.UP*2,p])
 for iy in 11:
  for ix in 17:
   var p:=Vector3(41.69+ix*.239,41.43+.066*iy,40.27)
   rays.append([p,p+Vector3.BACK*3])
 for ray:Array in rays:
  var a:Dictionary=stores[0].raycast_surface(ray[0],ray[1])
  var b:Dictionary=stores[1].raycast_surface(ray[0],ray[1])
  if a.hit:hits+=1
  if a.hit!=b.hit or (a.hit and Vector3(a.point).distance_to(b.point)>.0001):
   if agreeing:print("Inclined face mismatch ",ray," ",a," ",b)
   agreeing=false
 check(optimized>0 and hits>200 and agreeing,"Inclined sides, underside, tier and obstacle contacts agree with the volume boundary to 0.1 mm across a region seam")

func run_equilibrium()->void:
 await check_regional_prisms()
 check_level_section()
 check_inclined_faces()
 check_open_sheet()
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
 var wide:=AABB(Vector3(25,25,25),Vector3.ONE*40)
 var pocket_cells:Dictionary={left-Vector3i.RIGHT:[0,500,100000],left:[0,500,100000],sill:[300,500,0],right:[0,500,0]}
 water=fixture(pocket_cells)
 water.settle_after_edit(AABB(Vector3(sill)*.5,Vector3.ONE*.5))
 result=await solve(water)
 var reference:=amounts(water)
 check(result.ok and reference[left]==75000 and reference[right]==50000,"Scalar reference retains upstream water to the spill elevation")
 water=fixture(pocket_cells)
 water.settle_after_edit(wide)
 result=await solve(water,true)
 check(result.ok and result.get("wide_basin_leaves",0)==3 and amounts(water)==reference,"Wide compact spill with a merged two-column pool matches scalar quantities cell by cell: "+str(result))
 var upper_left:=Vector3i(83,88,83)
 var upper_right:=upper_left+Vector3i.RIGHT*2
 var cross_region:Dictionary={upper_left:[0,500,100000],upper_left+Vector3i.DOWN:[0,500,125000],
  upper_left+Vector3i.RIGHT:[300,500,0],upper_right:[0,500,0],upper_right+Vector3i.DOWN:[0,500,0]}
 water=fixture(cross_region)
 water.settle_after_edit(AABB(Vector3(upper_left)*.5,Vector3.ONE*.5))
 result=await solve(water)
 reference=amounts(water)
 check(result.ok and reference.get(upper_left)==75000 and reference.get(upper_right+Vector3i.DOWN)==25000,"Scalar spill across a region tier retains the water below the sill")
 water=fixture(cross_region);water.settle_after_edit(wide);result=await solve(water,true)
 check(result.ok and result.get("wide_basin_leaves",0)==3 and amounts(water)==reference,"Vertical column spill matches the scalar result above and below a region seam")
 var editable:=fixture({high:[0,500,125000],low:[0,500,0]})
 for attempt in 64:
  var packet:Dictionary=editable.next_mesh_batch()
  if packet.is_empty():break
  if packet.get("complete",false):check(editable.commit_mesh_batch(packet.batch),"Initial picking geometry published")
 editable.settle_after_edit(AABB(Vector3(low)*.5,Vector3.ONE*.5))
 var transaction:RefCounted=editable.capture_local_edit()
 var superseded:RefCounted=editable.capture_local_edit()
 if transaction!=null and superseded!=null:
  transaction.prepare([]);superseded.prepare([])
  check(amounts(editable)=={high:125000},"Preparing a complete resident edit leaves live quantities intact")
  var published:Dictionary=editable.accept_local_edit(transaction)
  check(published.get("resident_transaction",false) and amounts(editable)=={low:125000},"Accepting a resident edit transfers exactly the settled quantities")
  check(editable.accept_local_edit(transaction).is_empty() and editable.accept_local_edit(superseded).is_empty(),"Replayed or superseded resident edits leave the accepted state intact")
  check(published.has("batch") and editable.commit_mesh_batch(published.batch),"The same resident transaction supplies a publishable detailed picking surface")
 else:check(false,"Resident transaction acquired the bounded edit")
 editable=fixture(cross_region)
 for attempt in 64:
  var packet:Dictionary=editable.next_mesh_batch()
  if packet.is_empty():break
  if packet.complete:editable.commit_mesh_batch(packet.batch)
 editable.settle_after_edit(wide)
 transaction=editable.capture_local_edit(true)
 superseded=editable.capture_local_edit(true)
 if transaction!=null and superseded!=null:
  superseded.cancel();superseded.prepare([])
  check(editable.accept_local_edit(superseded).is_empty(),"Cancelled wide preparation preserves the old revision")
  transaction.prepare([])
  var published:Dictionary=editable.accept_local_edit(transaction)
  check(published.get("resident_transaction",false) and amounts(editable)==reference,"Wide local publication agrees with scalar spill on both sides of the region seam")
  check(published.has("batch") and editable.commit_mesh_batch(published.batch),"Wide edit supplies picking, immersion and the detailed render batch together")
  reopened=ClassDB.instantiate("NativeRegionalWater")
  check(reopened.restore_snapshot(snapshot(editable)) and amounts(reopened)==reference,"Wide local quantities persist across restart")
 else:check(false,"Wide field transaction captured the resident region seam")
 print("WATER_EQUILIBRIUM checks=",checks," failures=",failures)
 quit(failures)
