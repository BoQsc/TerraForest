# SPDX-License-Identifier: 0BSD
extends RefCounted
const SitePlan=preload("res://addons/structures/site_plan.gd")
const Quality=preload("res://addons/world_runtime/world_building_quality.gd")
static func recipe(center:Vector3)->Array:
 var sources:Array[Resource]=[]
 for floors in [2,3,4]:sources.append(preload("res://addons/structures/furniture_catalog.gd").furnished_tower(floors))
 var lots:Array=[]
 for street in [-52,0,52]:
  for side in [-1,1]:
   for x in [-24,24]:
    var index:int=lots.size()
    lots.append({"asset":sources[index%3],"origin":Vector3i(center)+Vector3i(x,0,street+side*16),"rotation":0 if side<0 else 2,"street_z":center.z+street,"label":"Northern lot %d"%(index+1)})
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
  var part:Dictionary=SitePlan.foundation(lot.asset,origin,lot.rotation,survey.grade)
  if not part.ok:return part
  # Preserve untouched natural ground where the floor already fits exactly.
  if absf(survey.min_height-survey.grade)>0.01 or absf(survey.max_height-survey.grade)>0.01:
   for segment:Dictionary in part.segments:segments.append(segment)
  protection=part.bounds if i==0 else protection.merge(part.bounds)
  modules.append(lot.asset)
  var offset:Vector3i=origin-target
  placements.append_array(PackedInt32Array([i,offset.x,offset.y,offset.z,lot.rotation]))
  # The tower stair ends at local Z=10. Start beyond it and meet the road.
  var a:=Vector3(0.5,0,10.5)
  for turn in lot.rotation:a=Vector3(1-a.z,a.y,a.x)
  a+=Vector3(origin)
  var b:=Vector3(a.x,center.y,lot.street_z)
  if absf(a.y-b.y)>Vector2(a.x-b.x,a.z-b.z).length()*0.25:return {"ok":false,"reason":"Entrance slope exceeds native limit"}
  paths.append(_segment(a,b,0.75,2,4,0,4))
 var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
 if not asset.compose(modules,placements):return {"ok":false,"reason":"Lot composition failed"}
 asset.resource_name="Northern neighborhood · independently fitted lots"
 var plan:Dictionary={"ok":true,"asset":asset,"target":target,"rotation":0,"bounds":protection,"segments":segments,"foundation_segments":segments.size(),"paving_segments":0,"street_width":8,"street_lines":PackedVector3Array(),"qualities":qualities,"lots":fitted}
 var roads:Array=[]
 for z in [-52,0,52]:
  var a:=center+Vector3(-50,0,z);var b:=center+Vector3(50,0,z)
  roads.append(_segment(a,b,4,1,4,0,4))
  plan.street_lines.append(a);plan.street_lines.append(b)
 for road:Dictionary in roads:plan.segments.append(road);plan.bounds=plan.bounds.merge(road.bounds)
 if not SitePlan._support_roads(plan,roads):return {"ok":false,"reason":"Road support outside world budget"}
 for path:Dictionary in paths:plan.segments.append(path);plan.bounds=plan.bounds.merge(path.bounds)
 plan.paving_segments=roads.size()+paths.size();plan.street_ends=plan.street_lines.slice(0,2)
 return plan
static func _segment(a:Vector3,b:Vector3,width:float,depth:float,clearance:float,shoulder:float,material:int)->Dictionary:
 var span:Vector3=b-a;var extent:float=width+shoulder
 var rise:float=absf(span.y)*extent/Vector2(span.x,span.z).length()
 var low:Vector3=a.min(b)-Vector3(extent,depth+rise,extent)
 var high:Vector3=a.max(b)+Vector3(extent,clearance+rise,extent)
 return {"start":a,"finish":b,"half_width":width,"depth":depth,"clearance":clearance,"shoulder":shoulder,"material":material,"bounds":AABB(low,high-low)}
