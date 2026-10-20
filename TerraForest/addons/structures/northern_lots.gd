# SPDX-License-Identifier: 0BSD
extends RefCounted
const SitePlan=preload("res://addons/structures/site_plan.gd")
const Quality=preload("res://addons/world_runtime/world_building_quality.gd")
static func recipe(center:Vector3)->Array:
 var catalog=preload("res://addons/structures/furniture_catalog.gd")
 var sources:Array[Resource]=[catalog.enclosed_cottage(),preload("res://addons/structures/workshop_catalog.gd").workshop(),catalog.furnished_tower(2),catalog.furnished_tower(3),catalog.furnished_tower(4),preload("res://addons/structures/workshop_catalog.gd").village_shop()]
 # Lower houses at the perimeter, workshops beside the streets, taller centre.
 var choices:Array[int]=[0,0,2,5,3,4,4,3,1,2,0,0]
 var lots:Array=[]
 for street in [-52,0,52]:
  for side in [-1,1]:
   for x in [-24,24]:
    var index:int=lots.size()
    lots.append({"asset":sources[choices[index]],"origin":Vector3i(center)+Vector3i(x,0,street+side*16),"rotation":0 if side<0 else 2,"street_z":center.z+street,"label":"Northern lot %d"%(index+1)})
 return lots
static func assemble(lots:Array,center:Vector3,surveys:Array)->Dictionary:
 if lots.size()!=12 or surveys.size()!=lots.size():return {"ok":false,"reason":"Incomplete lot survey"}
 var modules:Array[Resource]=[];var placements:=PackedInt32Array();var qualities:Array=[]
 var segments:Array[Dictionary]=[];var protection:=AABB();var paths:Array=[];var fitted:Array=[]
 var target:=Vector3i(center)
 for i in lots.size():
  var lot:Dictionary=lots[i];var survey:Dictionary=surveys[i].duplicate()
  if not survey.get("ok",false):return {"ok":false,"reason":"Missing survey for "+lot.label}
  # Keep short entrance approaches within the native road slope limit.
  var low:int=maxi(ceili(float(survey.max_height)-Quality.MAX_CUT),target.y-1)
  var high:int=mini(floori(float(survey.min_height)+Quality.MAX_FILL),target.y+1)
  if low>high:return {"ok":false,"reason":"Relocate lot: "+lot.label,"survey":survey}
  survey.grade=clampi(roundi((float(survey.min_height)+float(survey.max_height))*0.5),low,high)
  var quality:Dictionary=Quality.site(survey,lot.label);qualities.append(quality)
  if quality.status!="pass":return {"ok":false,"reason":"Lot exceeds earthworks budget","quality":quality}
  var origin:Vector3i=lot.origin;origin.y=survey.grade
  fitted.append({"asset":lot.asset,"origin":origin,"rotation":lot.rotation,"label":lot.label})
  # Narrow authoring strips limit capsule-end excavation outside the lot.
  var part:Dictionary=SitePlan.foundation(lot.asset,origin,lot.rotation,survey.grade,4.0)
  if not part.ok:return part
  # Preserve untouched natural ground where the floor already fits exactly.
  if absf(survey.min_height-survey.grade)>0.01 or absf(survey.max_height-survey.grade)>0.01:
   for segment:Dictionary in part.segments:segments.append(segment)
  protection=part.bounds if i==0 else protection.merge(part.bounds)
  modules.append(lot.asset)
  var offset:Vector3i=origin-target
  placements.append_array(PackedInt32Array([i,offset.x,offset.y,offset.z,lot.rotation]))
  # Start beyond each archetype's own approach, not a fixed tower distance.
  var local_bounds:AABB=lot.asset.placement_bounds(Vector3i.ZERO,0)
  var a:=Vector3(0.5,0,local_bounds.end.z+0.5)
  for turn in lot.rotation:a=Vector3(1-a.z,a.y,a.x)
  a+=Vector3(origin)
  var b:=Vector3(a.x,center.y,lot.street_z)
  if absf(a.y-b.y)>Vector2(a.x-b.x,a.z-b.z).length()*0.25:return {"ok":false,"reason":"Entrance slope exceeds native limit"}
  paths.append(_segment(a,b,0.75,2,4,0,4))
 var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
 if not asset.compose(modules,placements):return {"ok":false,"reason":"Lot composition failed"}
 asset.resource_name="Northern neighborhood · independently fitted lots"
 var plan:Dictionary={"ok":true,"asset":asset,"target":target,"rotation":0,"bounds":protection,"segments":segments,"foundation_segments":segments.size(),"paving_segments":0,"street_width":8,"street_lines":PackedVector3Array(),"qualities":qualities,"lots":fitted}
 var roads:Array=street_segments(center)
 for road:Dictionary in roads:
  plan.street_lines.append(road.start);plan.street_lines.append(road.finish)
 for road:Dictionary in roads:plan.segments.append(road);plan.bounds=plan.bounds.merge(road.bounds)
 if not SitePlan._support_roads(plan,roads):return {"ok":false,"reason":"Road support outside world budget"}
 var pavement:Dictionary=sidewalks(center)
 if not pavement.ok:return pavement
 plan.sidewalk_asset=pavement.asset;plan.sidewalk_origin=Vector3i(center)-Vector3i(0,1,0)
 for bed:Dictionary in pavement.beds:plan.segments.append(bed);plan.bounds=plan.bounds.merge(bed.bounds)
 var common:Dictionary=preload("res://addons/structures/neighborhood_common.gd").build(center)
 if not common.ok:return common
 plan.common=common
 for bed:Dictionary in common.segments:plan.segments.append(bed);plan.bounds=plan.bounds.merge(bed.bounds)
 for path:Dictionary in paths:plan.segments.append(path);plan.bounds=plan.bounds.merge(path.bounds)
 plan.paving_segments=roads.size()+paths.size();plan.street_ends=plan.street_lines.slice(0,2)
 return plan
static func sidewalks(center:Vector3)->Dictionary:
 var cells:Dictionary={};var beds:Array=[]
 # Two-metre inner sidewalks, interrupted at the arterial and entrance paths.
 for street in [-52,0,52]:
  for side in [-1,1]:
   var z:int=street+(4 if side>0 else -6)
   for x in range(-38,38):
    if absf(x+0.5)<8 or minf(absf(x+0.5+23.5),absf(x+0.5-24.5))<1.5:continue
    for dz in 2:cells[Vector3i(x,0,z+dz)]=65
   for ends:Array in [[-38,-8],[8,38]]:
    beds.append(_segment(center+Vector3(ends[0],-0.1,z+1),center+Vector3(ends[1],-0.1,z+1),1,1,4,0,1))
 for x in [-38,36]:
  for z in range(-56,58):
   if absf(z+0.5)<4 or absf(absf(z+0.5)-52)<4:continue
   for dx in 2:cells[Vector3i(x+dx,0,z)]=65
  for ends:Array in [[-48,-4],[4,48]]:
   beds.append(_segment(center+Vector3(x+1,-0.1,ends[0]),center+Vector3(x+1,-0.1,ends[1]),1,1,4,0,1))
 var records:=PackedInt32Array()
 for cell:Vector3i in cells:records.append_array(PackedInt32Array([cell.x,cell.y,cell.z,cells[cell]]))
 var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
 if not asset.configure(records):return {"ok":false,"reason":"Sidewalk block geometry rejected"}
 asset.resource_name="Northern concrete walkways"
 return {"ok":true,"asset":asset,"beds":beds}
static func street_segments(center:Vector3)->Array:
 var roads:Array=[]
 # Side streets join the three cross streets into a connected neighborhood loop.
 for z in [-52,0,52]:roads.append(_segment(center+Vector3(-42,0,z),center+Vector3(42,0,z),4,1,4,0,4))
 for x in [-42,42]:roads.append(_segment(center+Vector3(x,0,-52),center+Vector3(x,0,52),4,1,4,0,4))
 return roads
static func street_probe(center:Vector3)->Resource:
 var occupied:Dictionary={}
 for road:Dictionary in street_segments(center):
  var a:Vector3=road.start-center;var b:Vector3=road.finish-center
  var span:=b-a
  for x in range(floori(minf(a.x,b.x)-4),ceili(maxf(a.x,b.x)+4)+1):
   # Existing arterial is already paved and excluded from natural-root surveys.
   if absi(x)<8:continue
   for z in range(floori(minf(a.z,b.z)-4),ceili(maxf(a.z,b.z)+4)+1):
    var p:=Vector3(x,0,z);var near:Vector3=a+span*clampf((p-a).dot(span)/span.length_squared(),0,1)
    if p.distance_to(near)<=4:occupied[Vector2i(x,z)]=true
 var records:=PackedInt32Array()
 for p:Vector2i in occupied:records.append_array(PackedInt32Array([p.x,0,p.y,1]))
 var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
 return asset if asset.configure(records) else null
static func _segment(a:Vector3,b:Vector3,width:float,depth:float,clearance:float,shoulder:float,material:int)->Dictionary:
 var span:Vector3=b-a;var extent:float=width+shoulder
 var rise:float=absf(span.y)*extent/Vector2(span.x,span.z).length()
 var low:Vector3=a.min(b)-Vector3(extent,depth+rise,extent)
 var high:Vector3=a.max(b)+Vector3(extent,clearance+rise,extent)
 return {"start":a,"finish":b,"half_width":width,"depth":depth,"clearance":clearance,"shoulder":shoulder,"material":material,"bounds":AABB(low,high-low)}

# A small off-road bay, clear of homes, corner turning space and the tree groves.
static func parking(center:Vector3)->Dictionary:
 var start:=center+Vector3(0,0,70);var finish:=center+Vector3(-14,0,70)
 var records:=PackedInt32Array()
 # New ground and transition shoulder. The omitted |x|<8 strip is the already
 # paved, level regional arterial, not new earthworks or a natural-root surface.
 for x in range(-18,-7):
  for z in range(66,75):records.append_array(PackedInt32Array([x,0,z,1]))
 var probe:Resource=ClassDB.instantiate("NativeBlockPrefab")
 if not probe.configure(records):return {"ok":false}
 var road:Dictionary=_segment(start,finish,4,1,4,0,4)
 return {"ok":true,"start":start,"finish":finish,"bounds":road.bounds,"probe":probe,"pose":Transform3D(Basis(Vector3.UP,PI/2),center+Vector3(-10,0.85,70)),"paving_segments":1,"street_width":8,"street_ends":PackedVector3Array([start,finish])}
