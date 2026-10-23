# SPDX-License-Identifier: 0BSD
extends RefCounted
# Offline only. Native terrain samples and native AStar3D own field/path queries.
const Lots=preload("res://addons/structures/terrain_lot_planner.gd")
static func route(core,start:Vector3,finish:Vector3,reserved:Array)->Dictionary:
 return core.plan_regional_route(start,finish,reserved)

static func central_connection(core,town:Dictionary,layout:Dictionary,market:Dictionary={})->Dictionary:
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
 if not market.is_empty():
  finish=market.roads[0].start
  for road:Dictionary in market.roads:
   for p:Vector3 in [road.start,road.finish]:
    if p.z<finish.z or (p.z==finish.z and p.x>finish.x):finish=p
  for site:Dictionary in [town,market]:
   for lot:Dictionary in site.lots:
    var bounds:AABB=lot.bounds
    reserved.append(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(2))
 # Preserve the preferred route when valid, then try a bounded set of actual
 # street endpoints. A lexicographic extreme can lie beside a protected lot.
 var starts:=arrival_points(town,reserved,true)
 var finishes:=arrival_points(market,reserved,false) if not market.is_empty() else [finish]
 if starts.is_empty() or finishes.is_empty():return {"ok":false,"reason":"No unobstructed settlement road exit"}
 var last:Dictionary={}
 for a:Vector3 in starts:
  for b:Vector3 in finishes:
   last=route(core,a,b,reserved)
   if last.ok:return last
 return last

static func arrival_points(site:Dictionary,reserved:Array,south:bool)->Array:
 var points:Array=[]
 for road:Dictionary in site.roads:
  for point:Vector3 in [road.start,road.finish]:
   if points.has(point):continue
   var blocked:=false
   for area:Rect2 in reserved:
    # Matches native road-corridor clearance exactly.
    if area.grow(6).has_point(Vector2(point.x,point.z)):blocked=true;break
   if not blocked:points.append(point)
 points.sort_custom(func(a:Vector3,b:Vector3):
  if a.z==b.z:return a.x>b.x
  return a.z>b.z if south else a.z<b.z)
 return points.slice(0,8)
