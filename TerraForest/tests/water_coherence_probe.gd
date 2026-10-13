# SPDX-License-Identifier: 0BSD
extends RefCounted
static func components(water:RefCounted,rows:Array) -> Dictionary:
 var cells:Dictionary={}
 for row:Dictionary in rows:
  if row.distance_m<=3.0:cells[Vector3i(row.cell[0],row.cell[1],row.cell[2])]=row
 var seen:Dictionary={};var groups:Array=[]
 for seed:Vector3i in cells:
  if seen.has(seed):continue
  var pending:Array[Vector3i]=[seed];seen[seed]=true;var amount:=0;var count:=0
  while not pending.is_empty():
   var p:Vector3i=pending.pop_back();var a:Dictionary=cells[p];amount+=a.ml;count+=1
   for step:Vector3i in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.UP,Vector3i.DOWN,Vector3i.FORWARD,Vector3i.BACK]:
    var q:=p+step
    if seen.has(q) or not cells.has(q):continue
    # Connectivity now includes the reconstructed sloping free surface, not
    # the former constant head assumption. Its geometric predicates are also
    # checked independently in the native profile probe.
    var directions:Array[Vector3i]=[Vector3i.DOWN,Vector3i.RIGHT,Vector3i.LEFT,Vector3i.BACK,Vector3i.FORWARD,Vector3i.UP]
    var linked:bool=(int(a.geometry.connections)&(1<<directions.find(step)))!=0
    if linked:seen[q]=true;pending.append(q)
  groups.append({"cells":count,"ml":amount})
 var sum_ml:=0
 for group:Dictionary in groups:sum_ml+=group.ml
 print("GROUND_COMPONENTS ",JSON.stringify(groups))
 return {"radius_m":3,"components":groups,"water_ml":sum_ml,"scope":"Newly wet cells within three metres; boundary and pre-existing cells excluded"}
