# SPDX-License-Identifier: 0BSD
extends RefCounted
# Offline planning only. Never query or search this in a frame/streaming hot path.
# Survey undeveloped terrain, including every occupied foundation cell. A failed
# candidate is relocated, never made valid by increasing the earthworks budget.
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Quality=preload("res://addons/world_runtime/world_building_quality.gd")
const Lots=preload("res://addons/structures/northern_lots.gd")

static func streets(core,center:Vector3,source:Array=[])->Dictionary:
 var roads:Array=Lots.street_segments(center) if source.is_empty() else source
 var junctions:=PackedVector3Array()
 if source.is_empty():
  for x in [-42,42]:
   for z in [-52,0,52]:junctions.append(center+Vector3(x,0,z))
 else:
  for road:Dictionary in source:
   for p:Vector3 in [road.start,road.finish]:
    if not junctions.has(p):junctions.append(p)
 return core.plan_streets(roads,junctions)

static func heights(core,points:PackedVector3Array)->PackedFloat32Array:
 var result:=PackedFloat32Array()
 for start in range(0,points.size(),256):
  var batch:PackedVector3Array=points.slice(start,mini(start+256,points.size()))
  var query:=Codec.command(37,[batch.size()]);query.append_array(batch.to_byte_array())
  var reply:PackedByteArray=core.execute(query)
  if not Codec.reply_ok(reply) or reply.size()!=12+batch.size()*8:return PackedFloat32Array()
  for i in batch.size():result.append(reply.decode_float(12+i*8))
 return result

static func plan(core,center:Vector3,roads:Array=[],variant:int=0,recipe:Array=[])->Dictionary:
 var source:Array=Lots.recipe(center) if recipe.is_empty() else recipe
 var descriptors:Array=[]
 for index in source.size():
  var lot:Dictionary=source[index].duplicate()
  lot.asset=source[(index+variant)%source.size()].asset
  lot.bounds=lot.asset.placement_bounds(lot.origin,lot.rotation)
  lot.samples=lot.asset.foundation_samples(lot.origin,lot.rotation,0)
  lot.surface_offset=int(lot.asset.get_meta("site_surface_offset",0))
  var local_bounds:AABB=lot.asset.placement_bounds(Vector3i.ZERO,0)
  var entrance:=Vector3(0.5,lot.surface_offset,local_bounds.end.z+0.5)
  for turn in lot.rotation:entrance=Vector3(1-entrance.z,entrance.y,entrance.x)
  lot.entrance_local=entrance
  descriptors.append(lot)
 var result:Dictionary=core.plan_lots(center,descriptors,roads,recipe.is_empty())
 for lot:Dictionary in result.get("lots",[]):lot.quality=Quality.site(lot.survey,lot.label)
 return result

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
  var foundation:Dictionary=preload("res://addons/structures/site_plan.gd").foundation(lot.asset,lot.origin,lot.rotation,int(lot.survey.grade),4.0)
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
 # Underground clearance is part of the master plan, after all surface grading
 # and before any building is published. Later road support must not refill it.
 for lot:Dictionary in plan.lots:
  if not lot.asset.get_meta("cellar_clearance",false):continue
  var site=preload("res://addons/structures/site_plan.gd")
  var foundation:Dictionary=site.foundation(lot.asset,lot.origin,lot.rotation,int(lot.survey.grade))
  var complete:Dictionary=site.prepare(lot.asset,lot.origin,lot.rotation,int(lot.survey.grade))
  if not foundation.ok or not complete.ok:return {"ok":false,"reason":"Cellar preparation failed"}
  segments.append_array(complete.segments.slice(foundation.segments.size()))
 for segment:Dictionary in segments:
  bounds=segment.bounds if first else bounds.merge(segment.bounds);first=false
 return {"ok":true,"segments":segments,"bounds":bounds}

static func paving(plan:Dictionary)->Array:
 var poses:Array=[];var crossings:Array[Vector3]=[]
 for road:Dictionary in plan.roads:
  if road.start.distance_to(road.finish)<2:crossings.append((road.start+road.finish)*0.5)
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
    for junction:Vector3 in crossings:
     if Vector2(midpoint.x-junction.x,midpoint.z-junction.z).length()<6.5:crossing=true
    if crossing:continue
    var forward:Vector3=(b-a).normalized()
    var up:Vector3=forward.cross(across).normalized()
    var basis:=Basis(across*1.5,up*0.08,forward*(a.distance_to(b)+0.015))
    poses.append(Transform3D(basis,midpoint+up*(-0.04+0.015)))
 return poses
