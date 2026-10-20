# SPDX-License-Identifier: 0BSD
extends RefCounted
# Offline planning only. Never query or search this in a frame/streaming hot path.
# Survey undeveloped terrain, including every occupied foundation cell. A failed
# candidate is relocated, never made valid by increasing the earthworks budget.
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Quality=preload("res://addons/world_runtime/world_building_quality.gd")
const Lots=preload("res://addons/structures/northern_lots.gd")

static func streets(core,center:Vector3)->Dictionary:
 var vertices:Dictionary={};var edges:Array=[]
 # Shared endpoints force exact junction elevations. Small segments follow the
 # ground; a bounded constraint solve limits grade without flattening a district.
 for road:Dictionary in Lots.street_segments(center):
  var count:int=ceili(road.start.distance_to(road.finish)/14.0)*2
  var chain_start:int=edges.size()
  for i in count:
   var a:Vector3=road.start.lerp(road.finish,float(i)/count)
   var b:Vector3=road.start.lerp(road.finish,float(i+1)/count)
   var ka:=Vector2i(roundi(a.x*100),roundi(a.z*100))
   var kb:=Vector2i(roundi(b.x*100),roundi(b.z*100))
   for pair:Array in [[ka,a],[kb,b]]:
    if vertices.has(pair[0]):continue
    var p:Vector3=pair[1]
    # All directions at a shared node, including junction corners.
    var points:=PackedVector3Array()
    for dx in [-4,0,4]:
     for dz in [-4,0,4]:points.append(p+Vector3(dx,0,dz))
    var raw:PackedFloat32Array=heights(core,points)
    if raw.size()!=points.size():return {"ok":false,"reason":"Street survey failed"}
    var low:=INF;var high:=-INF
    for h in raw:low=minf(low,h);high=maxf(high,h)
    if high-3>low+2:return {"ok":false,"reason":"Street node exceeds earthworks budget","point":p}
    vertices[pair[0]]={"point":p,"low":high-3,"high":low+2,"grade":raw[4]}
   edges.append({"a":ka,"b":kb,"length":a.distance_to(b),"chain_start":chain_start,"chain_count":count})
 # Propagate feasible grade intervals, then choose compatible grades. Interval
 # rejection is a layout failure, not permission to increase the road slope.
 for iteration in 128:
  var changed:=false
  for edge:Dictionary in edges:
   var a:Dictionary=vertices[edge.a];var b:Dictionary=vertices[edge.b]
   var rise:float=edge.length*0.08
   for pair:Array in [[a,b],[b,a]]:
    var lo:float=maxf(pair[0].low,pair[1].low-rise)
    var hi:float=minf(pair[0].high,pair[1].high+rise)
    if lo>hi+0.0001:return {"ok":false,"reason":"Street requires a different route to meet 12% grade"}
    changed=changed or absf(lo-pair[0].low)>0.00001 or absf(hi-pair[0].high)>0.00001
    pair[0].low=lo;pair[0].high=hi
  if not changed:break
 # Both feasible envelopes are slope-compatible; their midpoint preserves this.
 var segments:Array=[];var max_fill:=0.0;var max_cut:=0.0
 for edge:Dictionary in edges:
  var a:Vector3=vertices[edge.a].point;var b:Vector3=vertices[edge.b].point
  a.y=(vertices[edge.a].low+vertices[edge.a].high)*0.5;b.y=(vertices[edge.b].low+vertices[edge.b].high)*0.5
  if absf(a.y-b.y)>edge.length*0.08001:return {"ok":false,"reason":"Street grade solver did not converge"}
  var across:Vector3=Vector3(-(b-a).z,0,(b-a).x).normalized()
  var points:=PackedVector3Array()
  for step in 9:
   for lateral in [-4,-2,0,2,4]:
    var p:Vector3=a.lerp(b,step/8.0)+across*lateral
    p.y=lerpf(a.y,b.y,smoothstep(0.0,1.0,step/8.0));points.append(p)
  var raw:PackedFloat32Array=heights(core,points)
  if raw.size()!=points.size():return {"ok":false,"reason":"Street surface survey failed"}
  for i in points.size():
   var fill:float=points[i].y-raw[i]
   max_fill=maxf(max_fill,fill);max_cut=maxf(max_cut,-fill)
   if fill>2.001 or fill< -3.001:return {"ok":false,"reason":"Street interior exceeds earthworks budget","point":points[i]}
  segments.append(Lots._segment(a,b,4,1,4,0,4))
 for i in segments.size():
  var edge:Dictionary=edges[i];var coefficients:=PackedFloat64Array()
  for j in range(edge.chain_start,edge.chain_start+edge.chain_count):
   var segment:Dictionary=segments[j];var delta:float=segment.finish.y-segment.start.y
   coefficients.append_array(PackedFloat64Array([-2*delta,3*delta,0,segment.start.y]))
  segments[i]["coefficients"]=coefficients;segments[i]["curve_index"]=i-edge.chain_start
 # Shared level junction footprints, applied after adjoining sloped roads.
 for x in [-42,42]:
  for z in [-52,0,52]:
   var key:=Vector2i(roundi((center.x+x)*100),roundi((center.z+z)*100))
   var vertex:Dictionary=vertices[key]
   var p:Vector3=vertex.point;p.y=(vertex.low+vertex.high)*0.5
   var probes:=PackedVector3Array()
   for dx in range(-4,5):
    for dz in range(-4,5):
     if Vector2(dx,dz).length()<=4:probes.append(p+Vector3(dx,0,dz))
   var raw:PackedFloat32Array=heights(core,probes)
   if raw.size()!=probes.size():return {"ok":false,"reason":"Junction survey failed"}
   for h in raw:
    if p.y-h>2 or h-p.y>3:return {"ok":false,"reason":"Junction exceeds earthworks budget"}
   var junction:Dictionary=Lots._segment(p-Vector3(0.5,0,0),p+Vector3(0.5,0,0),4,3,4,2,4)
   junction["coefficients"]=PackedFloat64Array([0,0,0,p.y]);junction["curve_index"]=0
   segments.append(junction)
 return {"ok":true,"segments":segments,"max_fill":max_fill,"max_cut":max_cut}

static func heights(core,points:PackedVector3Array)->PackedFloat32Array:
 var result:=PackedFloat32Array()
 for start in range(0,points.size(),256):
  var batch:PackedVector3Array=points.slice(start,mini(start+256,points.size()))
  var query:=Codec.command(37,[batch.size()]);query.append_array(batch.to_byte_array())
  var reply:PackedByteArray=core.execute(query)
  if not Codec.reply_ok(reply) or reply.size()!=12+batch.size()*8:return PackedFloat32Array()
  for i in batch.size():result.append(reply.decode_float(12+i*8))
 return result

static func frontage(core,lot:Dictionary,origin:Vector3i,roads:Array)->Dictionary:
 var bounds:AABB=lot.asset.placement_bounds(Vector3i.ZERO,0)
 var a:=Vector3(0.5,0,bounds.end.z+0.5)
 for turn in lot.rotation:a=Vector3(1-a.z,a.y,a.x)
 a+=Vector3(origin)
 var b:=Vector3(a.x,0,lot.street_z)
 var found:=false
 for road:Dictionary in roads:
  if absf(road.start.z-b.z)>0.001 or absf(road.finish.z-b.z)>0.001:continue
  if b.x<minf(road.start.x,road.finish.x) or b.x>maxf(road.start.x,road.finish.x):continue
  b.y=lerpf(road.start.y,road.finish.y,smoothstep(0.0,1.0,(b.x-road.start.x)/(road.finish.x-road.start.x)))
  found=true;break
 if not found:return {"ok":false}
 var length:float=Vector2(a.x-b.x,a.z-b.z).length()
 if length<0.01 or absf(a.y-b.y)>length*0.25:return {"ok":false}
 var points:=PackedVector3Array()
 for step in range(ceili(length*2)+1):
  var p:Vector3=a.lerp(b,float(step)/ceili(length*2))
  for dx in [-0.75,0,0.75]:points.append(p+Vector3(dx,0,0))
 var raw:PackedFloat32Array=heights(core,points)
 if raw.size()!=points.size():return {"ok":false}
 for i in points.size():
  if points[i].y-raw[i]>2 or raw[i]-points[i].y>3:return {"ok":false}
 return {"ok":true,"segment":Lots._segment(a,b,0.75,1,4,0,1)}

static func plan(core,center:Vector3,roads:Array=[])->Dictionary:
 var fitted:Array=[];var reserved:Array[AABB]=[];var rejected:Array=[]
 var source:Array=Lots.recipe(center)
 for index in source.size():
  var lot:Dictionary=source[index]
  var best:Dictionary={};var best_cost:=INF
  # Bounded 25-location search within each original frontage zone.
  # Reserve streets independently; no building may occupy their corridors.
  for dx in [0,-3,3,-6,6]:
   for dz in [0,-3,3,-6,6]:
    var origin:Vector3i=lot.origin+Vector3i(dx,0,dz)
    var bounds:AABB=lot.asset.placement_bounds(origin,lot.rotation)
    var blocked:=false
    for occupied:AABB in reserved:
     var a:=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(2)
     var b:=Rect2(Vector2(occupied.position.x,occupied.position.z),Vector2(occupied.size.x,occupied.size.z))
     if a.intersects(b):blocked=true;break
    if blocked:continue
    var points:PackedVector3Array=lot.asset.foundation_samples(origin,lot.rotation,0)
    for point:Vector3 in points:
     if absf(point.x-center.x)<8:blocked=true;break
     for street in [-52,0,52]:
      if absf(point.z-center.z-street)<5:blocked=true;break
     if blocked:break
     if absf(absf(point.x-center.x)-42)<5 and absf(point.z-center.z)<=57:blocked=true;break
    if blocked:continue
    var raw:PackedFloat32Array=heights(core,points)
    if raw.size()!=points.size():return {"ok":false,"reason":"Native raw survey failed"}
    var low:=INF;var high:=-INF
    for h in raw:low=minf(low,h);high=maxf(high,h)
    var minimum:int=ceili(high-Quality.MAX_CUT)
    var maximum:int=floori(low+Quality.MAX_FILL)
    if minimum>maximum:continue
    var grade:int=clampi(roundi((low+high)*0.5),minimum,maximum)
    var entrance:Dictionary={}
    if not roads.is_empty():
     var grade_found:=false
     for candidate_grade in range(minimum,maximum+1):
      var candidate:=Vector3i(origin.x,candidate_grade,origin.z)
      var path:Dictionary=frontage(core,lot,candidate,roads)
      if path.ok and (not grade_found or absf(candidate_grade-(low+high)*0.5)<absf(grade-(low+high)*0.5)):
       grade=candidate_grade;entrance=path;grade_found=true
     if not grade_found:continue
    var cost:float=high-low+0.04*(absf(dx)+absf(dz))
    if cost>=best_cost:continue
    var survey:Dictionary={"ok":true,"min_height":low,"max_height":high,"grade":grade}
    var quality:Dictionary=Quality.site(survey,lot.label)
    if quality.status!="pass":continue
    origin.y=grade
    best={"asset":lot.asset,"origin":origin,"rotation":lot.rotation,"label":lot.label,
     "street_z":lot.street_z,"survey":survey,"quality":quality,
     "sample_count":points.size(),"bounds":lot.asset.placement_bounds(origin,lot.rotation),"entrance":entrance}
    best_cost=cost
  if best.is_empty():rejected.append(lot.label)
  else:fitted.append(best);reserved.append(best.bounds)
 # Missing buildings are explicit rejection, never a silently sparser success.
 return {"ok":rejected.is_empty(),"lots":fitted,"rejected":rejected,
  "reason":"" if rejected.is_empty() else "Frontage zones require relocation or a different street layout"}

static func locate(core,center:Vector3)->Dictionary:
 var attempts:=0
 for dx in [0,-24,24,-48,48,-72,72,-96,96]:
  for dz in [0,-24,24,-48,48,-72,72,-96,96]:
   var candidate:=center+Vector3(dx,0,dz)
   if candidate.x<120 or candidate.z<120 or candidate.x>1880 or candidate.z>1880:continue
   attempts+=1
   var roads:Dictionary=streets(core,candidate)
   if not roads.ok:continue
   var lots:Dictionary=plan(core,candidate,roads.segments)
   if lots.ok:return {"ok":true,"center":candidate,"lots":lots.lots,"roads":roads.segments,"attempts":attempts}
 return {"ok":false,"reason":"No complete terrain-fitting layout in bounded search","attempts":attempts}

static func earthworks(plan:Dictionary)->Dictionary:
 if not plan.get("ok",false):return {"ok":false,"reason":"Incomplete layout"}
 var segments:Array=[];var bounds:=AABB();var first:=true
 for lot:Dictionary in plan.lots:
  var foundation:Dictionary=preload("res://addons/structures/site_plan.gd").foundation(lot.asset,lot.origin,lot.rotation,lot.origin.y,4.0)
  if not foundation.ok:return foundation
  for strip:Dictionary in foundation.segments:
   # Only the surveyed 2m fill / 3m cut is needed. Keep transition shoulders
   # local so one building's foundation cannot flatten adjacent streets.
   segments.append(Lots._segment(strip.start,strip.finish,strip.half_width,3,4,2,1))
 for lot:Dictionary in plan.lots:
  var path:Dictionary=lot.entrance.segment
  segments.append(Lots._segment(path.start,path.finish,path.half_width,3,4,1,1))
 for road:Dictionary in plan.roads:
  var segment:Dictionary=Lots._segment(road.start,road.finish,road.half_width,3,4,2,4)
  segment["coefficients"]=road.coefficients;segment["curve_index"]=road.curve_index
  segments.append(segment)
 for segment:Dictionary in segments:
  bounds=segment.bounds if first else bounds.merge(segment.bounds);first=false
 return {"ok":true,"segments":segments,"bounds":bounds}
