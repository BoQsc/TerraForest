# SPDX-License-Identifier: 0BSD
extends RefCounted
# Offline only. Native terrain samples and native AStar3D own field/path queries.
const Lots=preload("res://addons/structures/terrain_lot_planner.gd")
const Segment=preload("res://addons/structures/northern_lots.gd")
const STEP:=16.0
const WIDTH:=4.0
static func clear(a:Vector3,b:Vector3,reserved:Array)->bool:
 for area:Rect2 in reserved:
  var grown:Rect2=area.grow(WIDTH+2)
  var count:int=maxi(1,ceili(Vector2(b.x-a.x,b.z-a.z).length()/2))
  for i in count+1:
   var p:Vector3=a.lerp(b,float(i)/count)
   if grown.has_point(Vector2(p.x,p.z)):return false
 return true
static func survey(core,a:Vector3,b:Vector3,reserved:Array)->bool:
 var span:=b-a;var length:=Vector2(span.x,span.z).length()
 if length<1 or length>128 or absf(span.y)>length*0.12 or not clear(a,b,reserved):return false
 var across:=Vector3(-span.z,0,span.x).normalized()
 var points:=PackedVector3Array();var count:int=ceili(length/2)
 for i in count+1:
  for side in [-5.0,0,5.0]:points.append(a.lerp(b,float(i)/count)+across*side)
 var raw:PackedFloat32Array=Lots.heights(core,points)
 if raw.size()!=points.size():return false
 for i in points.size():
  if points[i].y-raw[i]>2 or raw[i]-points[i].y>3:return false
 return true
static func route(core,start:Vector3,finish:Vector3,reserved:Array)->Dictionary:
 if not start.is_finite() or not finish.is_finite():return {"ok":false,"reason":"Invalid endpoints"}
 var low:Vector3=start.min(finish)-Vector3(256,0,256)
 var high:Vector3=start.max(finish)+Vector3(256,0,256)
 low.x=maxf(16,floorf(low.x/STEP)*STEP);low.z=maxf(16,floorf(low.z/STEP)*STEP)
 high.x=minf(1984,ceilf(high.x/STEP)*STEP);high.z=minf(1984,ceilf(high.z/STEP)*STEP)
 var nx:int=int((high.x-low.x)/STEP)+1;var nz:int=int((high.z-low.z)/STEP)+1
 if nx*nz>15625:return {"ok":false,"reason":"Route search exceeds world bound"}
 var samples:=PackedVector3Array()
 for z in nz:
  for x in nx:samples.append(Vector3(low.x+x*STEP,0,low.z+z*STEP))
 var heights:PackedFloat32Array=Lots.heights(core,samples)
 if heights.size()!=samples.size():return {"ok":false,"reason":"Native route survey failed"}
 var graph:=AStar3D.new();graph.reserve_space(samples.size()+2)
 for i in samples.size():
  samples[i].y=heights[i]
  if clear(samples[i],samples[i],reserved):graph.add_point(i,samples[i])
 for z in nz:
  for x in nx:
   var id:int=z*nx+x
   if not graph.has_point(id):continue
   for offset:Vector2i in [Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(-1,1)]:
    var xx:int=x+offset.x;var zz:int=z+offset.y
    if xx<0 or xx>=nx or zz>=nz:continue
    var next:int=zz*nx+xx
    if not graph.has_point(next):continue
    var span:Vector3=samples[next]-samples[id]
    if absf(span.y)<=Vector2(span.x,span.z).length()*0.12 and clear(samples[id],samples[next],reserved):graph.connect_points(id,next)
 var source:int=samples.size();var target:int=source+1
 graph.add_point(source,start);graph.add_point(target,finish)
 for pair:Array in [[source,start],[target,finish]]:
  var x:int=roundi((pair[1].x-low.x)/STEP);var z:int=roundi((pair[1].z-low.z)/STEP)
  for dz in range(-2,3):
   for dx in range(-2,3):
    var xx:int=x+dx;var zz:int=z+dz
    if xx<0 or zz<0 or xx>=nx or zz>=nz:continue
    var id:int=zz*nx+xx
    if graph.has_point(id) and survey(core,pair[1],samples[id],reserved):graph.connect_points(pair[0],id)
 # Refine only requested corridors. Invalid edges are removed, never relaxed.
 for attempt in 32:
  var ids:PackedInt64Array=graph.get_id_path(source,target)
  if ids.is_empty():return {"ok":false,"reason":"No route fits terrain and exclusions","nodes":graph.get_point_count()}
  var valid:=true
  for i in range(1,ids.size()):
   if not survey(core,graph.get_point_position(ids[i-1]),graph.get_point_position(ids[i]),reserved):
    graph.disconnect_points(ids[i-1],ids[i]);valid=false
  if not valid:continue
  var points:=PackedVector3Array([start]);var index:=0
  # Remove grid zigzags only when the entire replacement corridor passes survey.
  while index<ids.size()-1:
   var next:int=mini(ids.size()-1,index+6)
   while next>index+1 and not survey(core,graph.get_point_position(ids[index]),graph.get_point_position(ids[next]),reserved):next-=1
   points.append(graph.get_point_position(ids[next]));index=next
  var segments:Array=[];var bounds:=AABB();var first:=true
  for material in [1,4]:
   for i in range(1,points.size()):
    var part:Dictionary=Segment._segment(points[i-1],points[i],5 if material==1 else WIDTH,3,4,1 if material==1 else 0,material)
    segments.append(part);bounds=part.bounds if first else bounds.merge(part.bounds);first=false
  return {"ok":true,"points":points,"segments":segments,"bounds":bounds,"nodes":graph.get_point_count(),"attempts":attempt+1}
 return {"ok":false,"reason":"Route refinement limit reached"}

static func central_connection(core,town:Dictionary,layout:Dictionary)->Dictionary:
 var start:Vector3=town.roads[0].start
 for road:Dictionary in town.roads:
  for point:Vector3 in [road.start,road.finish]:
   if point.z>start.z or (point.z==start.z and point.x>start.x):start=point
 var finish:Vector3=layout.sites[0].position
 var heights:PackedFloat32Array=Lots.heights(core,PackedVector3Array([finish]))
 if heights.size()!=1:return {"ok":false,"reason":"Central arrival survey failed"}
 finish.y=heights[0]
 var protected:Dictionary=Lots.reservations(core,layout.sites[3].position)
 if not protected.ok:return {"ok":false,"reason":"Region reservations unavailable"}
 var reserved:Array=protected.areas.duplicate()
 var central:Rect2=Rect2(Vector2(finish.x,finish.z)-Vector2.ONE*(layout.sites[0].radius+32),Vector2.ONE*(layout.sites[0].radius+32)*2)
 var index:int=reserved.find(central)
 if index<0:return {"ok":false,"reason":"Central destination reservation missing"}
 reserved.remove_at(index)
 return route(core,start,finish,reserved)
