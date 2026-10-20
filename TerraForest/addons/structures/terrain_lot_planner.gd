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
    for dx in [-5.5,0,5.5]:
     for dz in [-5.5,0,5.5]:points.append(p+Vector3(dx,0,dz))
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
 var segments:Array=[];var max_fill:=0.0;var max_cut:=0.0;var earthwork_sum:=0.0;var earthwork_samples:=0
 for edge:Dictionary in edges:
  var a:Vector3=vertices[edge.a].point;var b:Vector3=vertices[edge.b].point
  a.y=(vertices[edge.a].low+vertices[edge.a].high)*0.5;b.y=(vertices[edge.b].low+vertices[edge.b].high)*0.5
  if absf(a.y-b.y)>edge.length*0.08001:return {"ok":false,"reason":"Street grade solver did not converge"}
  var across:Vector3=Vector3(-(b-a).z,0,(b-a).x).normalized()
  var points:=PackedVector3Array()
  for step in 9:
   for lateral in [-5.5,-4,-2,0,2,4,5.5]:
    var p:Vector3=a.lerp(b,step/8.0)+across*lateral
    p.y=lerpf(a.y,b.y,smoothstep(0.0,1.0,step/8.0));points.append(p)
  var raw:PackedFloat32Array=heights(core,points)
  if raw.size()!=points.size():return {"ok":false,"reason":"Street surface survey failed"}
  for i in points.size():
   var fill:float=points[i].y-raw[i]
   earthwork_sum+=absf(fill);earthwork_samples+=1
   max_fill=maxf(max_fill,fill);max_cut=maxf(max_cut,-fill)
   if fill>2.001 or fill< -3.001:return {"ok":false,"reason":"Street interior exceeds earthworks budget","point":points[i]}
  segments.append(Lots._segment(a,b,3,1,4,0,4))
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
   for dx in range(-6,7):
    for dz in range(-6,7):
     if Vector2(dx,dz).length()<=5.5:probes.append(p+Vector3(dx,0,dz))
   var raw:PackedFloat32Array=heights(core,probes)
   if raw.size()!=probes.size():return {"ok":false,"reason":"Junction survey failed"}
   for h in raw:
    if p.y-h>2 or h-p.y>3:return {"ok":false,"reason":"Junction exceeds earthworks budget"}
   var junction:Dictionary=Lots._segment(p-Vector3(0.5,0,0),p+Vector3(0.5,0,0),3,3,4,2,4)
   junction["coefficients"]=PackedFloat64Array([0,0,0,p.y]);junction["curve_index"]=0
   segments.append(junction)
 return {"ok":true,"segments":segments,"max_fill":max_fill,"max_cut":max_cut,"mean_earthwork":earthwork_sum/maxi(1,earthwork_samples)}

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

static func plan(core,center:Vector3,roads:Array=[],variant:int=0)->Dictionary:
 var fitted:Array=[];var reserved:Array[AABB]=[];var rejected:Array=[]
 var source:Array=Lots.recipe(center)
 for index in source.size():
  var lot:Dictionary=source[index].duplicate()
  lot.asset=source[(index+variant)%source.size()].asset
  var best:Dictionary={};var best_cost:=INF
  # Bounded 49-location search within each original frontage zone.
  # Reserve streets independently; no building may occupy their corridors.
  for dx in [0,-3,3,-6,6,-9,9]:
   for dz in [0,-3,3,-6,6,-9,9]:
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
      if absf(point.z-center.z-street)<6.5:blocked=true;break
     if blocked:break
     if absf(absf(point.x-center.x)-42)<6.5 and absf(point.z-center.z)<=57:blocked=true;break
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

# Planning reservations come from the same native world instance being surveyed.
# They are exclusions, never public map markers or evidence of baked construction.
static func reservations(core,origin:Vector3)->Dictionary:
 var result:Array[Rect2]=[]
 var lakes:PackedByteArray=core.execute(Codec.command(27))
 if not Codec.reply_ok(lakes) or lakes.size()<16:return {"ok":false}
 var count:int=lakes.decode_u32(12)
 if count>64 or lakes.size()!=16+count*44:return {"ok":false}
 for i in count:
  var at:int=16+i*44;var spacing:float=lakes.decode_float(at+24)
  var low:=Vector2(lakes.decode_float(at),lakes.decode_float(at+8))
  var size:=Vector2(lakes.decode_u32(at+12),lakes.decode_u32(at+20))*spacing
  # Preserve the catalog volume and a 12 m shore/access margin.
  result.append(Rect2(low,size).grow(12))
 var sites:PackedByteArray=core.execute(Codec.command(34))
 if not Codec.reply_ok(sites) or sites.size()!=168:return {"ok":false}
 var owner:=-1;var closest:=INF
 for i in 5:
  var at:int=16+i*20
  var point:=Vector2(sites.decode_float(at),sites.decode_float(at+8))
  var distance:float=point.distance_squared_to(Vector2(origin.x,origin.z))
  if distance<closest:closest=distance;owner=i
 for i in 5:
  if i==owner:continue
  var at:int=16+i*20
  var point:=Vector2(sites.decode_float(at),sites.decode_float(at+8))
  var radius:float=sites.decode_float(at+12)+32
  result.append(Rect2(point-Vector2.ONE*radius,Vector2.ONE*radius*2))
 var mine:PackedByteArray=core.execute(Codec.command(35))
 if not Codec.reply_ok(mine) or mine.size()!=76:return {"ok":false}
 var low:=Vector2(mine.decode_float(44),mine.decode_float(52))
 var high:=Vector2(mine.decode_float(56),mine.decode_float(64))
 result.append(Rect2(low,high-low).grow(12))
 var entrance:=Vector2(mine.decode_float(32),mine.decode_float(40))
 result.append(Rect2(entrance-Vector2(16,16),Vector2(32,32)))
 return {"ok":true,"areas":result,"owner":owner}

static func footprint_clear(bounds:AABB,reserved:Array)->bool:
 var footprint:=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
 for area:Rect2 in reserved:
  if footprint.intersects(area):return false
 return true

static func locate(core,center:Vector3)->Dictionary:
 var protected:Dictionary=reservations(core,center)
 if not protected.ok:return {"ok":false,"reason":"Native region reservations unavailable","attempts":0}
 var attempts:=0;var reasons:Dictionary={};var best_missing:=12
 var candidates:Array=[]
 for dx in [0,-24,24,-48,48,-72,72,-96,96,-120,120,-144,144,-168,168,-192,192,-216,216,-240,240,-264,264,-288,288]:
  for dz in [0,-24,24,-48,48,-72,72,-96,96,-120,120,-144,144,-168,168,-192,192,-216,216,-240,240,-264,264,-288,288]:
   var candidate:=center+Vector3(dx,0,dz)
   if candidate.x<120 or candidate.z<120 or candidate.x>1880 or candidate.z>1880:continue
   attempts+=1
   # Conservative recipe envelope includes shifted plots, paths and shoulders.
   if not footprint_clear(AABB(candidate-Vector3(75,0,100),Vector3(150,256,200)),protected.areas):
    reasons["Reserved lake, POI or neighboring site"]=int(reasons.get("Reserved lake, POI or neighboring site",0))+1;continue
   var roads:Dictionary=streets(core,candidate)
   if not roads.ok:
    reasons[roads.reason]=int(reasons.get(roads.reason,0))+1;continue
   # A permitted excavation is not necessarily a desirable location. Rank all
   # bounded candidates before trying buildings; prefer little ground disturbance.
   var cost:float=roads.mean_earthwork+0.3*(roads.max_cut+roads.max_fill)+0.001*center.distance_to(candidate)
   candidates.append({"center":candidate,"roads":roads,"cost":cost,"order":attempts})
 candidates.sort_custom(func(a:Dictionary,b:Dictionary):return a.cost<b.cost if a.cost!=b.cost else a.order<b.order)
 for candidate:Dictionary in candidates:
  for variant in [0,1,2,3]:
   var lots:Dictionary=plan(core,candidate.center,candidate.roads.segments,variant)
   best_missing=mini(best_missing,lots.rejected.size())
   if lots.ok:
    var checked:Dictionary={"ok":true,"lots":lots.lots,"roads":candidate.roads.segments}
    var works:Dictionary=earthworks(checked)
    if not works.ok or not footprint_clear(works.bounds,protected.areas):continue
    return {"ok":true,"center":candidate.center,"lots":lots.lots,"roads":candidate.roads.segments,"attempts":attempts,"variant":variant,
    "site_cost":candidate.cost,"mean_earthwork":candidate.roads.mean_earthwork,"max_cut":candidate.roads.max_cut,"max_fill":candidate.roads.max_fill,"ranked_candidates":candidates.size()}
 return {"ok":false,"reason":"No complete terrain-fitting layout in bounded search","attempts":attempts,"road_rejections":reasons,"best_missing":best_missing}

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
  var support:Dictionary=Lots._segment(road.start,road.finish,5.5,3,4,2,1)
  support["coefficients"]=road.coefficients;support["curve_index"]=road.curve_index
  segments.append(support)
 for road:Dictionary in plan.roads:
  var segment:Dictionary=Lots._segment(road.start,road.finish,road.half_width,3,4,0,4)
  segment["coefficients"]=road.coefficients;segment["curve_index"]=road.curve_index
  segments.append(segment)
 for segment:Dictionary in segments:
  bounds=segment.bounds if first else bounds.merge(segment.bounds);first=false
 return {"ok":true,"segments":segments,"bounds":bounds}

static func paving(plan:Dictionary)->Array:
 var poses:Array=[]
 for road:Dictionary in plan.roads:
  var span:Vector3=road.finish-road.start
  var horizontal:float=Vector2(span.x,span.z).length()
  if horizontal<2:continue # Shared junctions stay flush asphalt crossings.
  var steps:int=ceili(horizontal/2.0)
  var across:Vector3=Vector3.UP.cross(span).normalized()
  for i in steps:
   var a:Vector3=road.start.lerp(road.finish,float(i)/steps)
   var b:Vector3=road.start.lerp(road.finish,float(i+1)/steps)
   a.y=lerpf(road.start.y,road.finish.y,smoothstep(0,1,float(i)/steps))
   b.y=lerpf(road.start.y,road.finish.y,smoothstep(0,1,float(i+1)/steps))
   for side in [-1,1]:
    var midpoint:Vector3=(a+b)*0.5+across*side*3.75
    var crossing:=false
    for x in [-42,42]:
     for z in [-52,0,52]:
      if Vector2(midpoint.x-plan.center.x-x,midpoint.z-plan.center.z-z).length()<6.5:crossing=true
    if crossing:continue
    var forward:Vector3=(b-a).normalized()
    var up:Vector3=forward.cross(across).normalized()
    var basis:=Basis(across*1.5,up*0.08,forward*(a.distance_to(b)+0.015))
    poses.append(Transform3D(basis,midpoint+up*(-0.04+0.015)))
 return poses
