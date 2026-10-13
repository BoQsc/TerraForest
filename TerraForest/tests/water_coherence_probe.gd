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
    var b:Dictionary=cells[q];var linked:=false
    if step.y!=0:
     var low:Dictionary=a if step.y>0 else b;var high:Dictionary=b if step.y>0 else a
     linked=low.ml>=low.geometry.capacity_ml and high.geometry.bottom<=low.geometry.head+0.00001
    else:
     var edge:Vector3=(Vector3(p)+Vector3(q))*0.25+Vector3.ONE*0.25
     var tangent:=Vector3.FORWARD if step.x!=0 else Vector3.RIGHT
     var a_min:=INF;var b_min:=INF
     for sign_value in [-1,1]:
      var corner:Vector3=edge+tangent*0.2499*sign_value
      a_min=minf(a_min,water.cell_geometry(corner-Vector3(step)*0.0001).bottom)
      b_min=minf(b_min,water.cell_geometry(corner+Vector3(step)*0.0001).bottom)
     var opening:=maxf(a_min,b_min)
     linked=a.geometry.head>opening and b.geometry.head>opening
    if linked:seen[q]=true;pending.append(q)
  groups.append({"cells":count,"ml":amount})
 var sum_ml:=0
 for group:Dictionary in groups:sum_ml+=group.ml
 print("GROUND_COMPONENTS ",JSON.stringify(groups))
 return {"radius_m":3,"components":groups,"water_ml":sum_ml,"scope":"Newly wet cells within three metres; boundary and pre-existing cells excluded"}
