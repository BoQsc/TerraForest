# SPDX-License-Identifier: 0BSD
extends RefCounted
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
const Lots=preload("res://addons/structures/northern_lots.gd")
static func recipe(center:Vector3)->Array:
 var cottage=preload("res://addons/structures/furniture_catalog.gd").enclosed_cottage()
 var workshop=preload("res://addons/structures/workshop_catalog.gd").workshop()
 var shop=preload("res://addons/structures/workshop_catalog.gd").village_shop()
 var cellar=preload("res://addons/structures/cellar_catalog.gd").cottage()
 var assets:Array=[cellar,shop,workshop,cottage,cottage,workshop,shop,cottage]
 var result:Array=[]
 for street in [-24,24]:
  for side in [-1,1]:
   for x in [-22,22]:
    result.append({"asset":assets[result.size()],"origin":Vector3i(center)+Vector3i(x,0,street+side*15),"rotation":0 if side<0 else 2,"street_z":center.z+street,"label":"Market lot %d"%(result.size()+1)})
 return result
static func locate(core,hint:Vector3,occupied:AABB)->Dictionary:
 var reservations:Dictionary=Planner.reservations(core,hint)
 if not reservations.ok:return {"ok":false,"reason":"Market reservations unavailable"}
 var reserved:Array=reservations.areas.duplicate()
 reserved.append(Rect2(Vector2(occupied.position.x,occupied.position.z),Vector2(occupied.size.x,occupied.size.z)).grow(16))
 var candidates:Array=[]
 var survey_usec:=0;var recipe_usec:=0;var fitting_usec:=0;var attempts:=0
 for dx in [0,-24,24,-48,48,-72,72,-96,96,-120,120,-144,144]:
  for dz in [0,-24,24,-48,48,-72,72,-96,96,-120,120,-144,144]:
   var center:Vector3=hint+Vector3(dx,0,dz)
   if not Planner.footprint_clear(AABB(center-Vector3(70,0,70),Vector3(140,256,140)),reserved):continue
   var lines:Array=[]
   for z in [-24,24]:lines.append(Lots._segment(center+Vector3(-44,0,z),center+Vector3(44,0,z),3,3,4,0,4))
   for x in [-44,44]:lines.append(Lots._segment(center+Vector3(x,0,-24),center+Vector3(x,0,24),3,3,4,0,4))
   var begun:=Time.get_ticks_usec()
   var roads:Dictionary=Planner.streets(core,center,lines)
   survey_usec+=Time.get_ticks_usec()-begun
   if roads.ok:candidates.append({"center":center,"roads":roads,"cost":roads.mean_earthwork+0.3*(roads.max_cut+roads.max_fill)+0.001*center.distance_to(hint)})
 candidates.sort_custom(func(a:Dictionary,b:Dictionary):return a.cost<b.cost)
 for candidate:Dictionary in candidates:
  attempts+=1
  var begun:=Time.get_ticks_usec()
  var assets:Array=recipe(candidate.center)
  recipe_usec+=Time.get_ticks_usec()-begun;begun=Time.get_ticks_usec()
  var lots:Dictionary=Planner.plan(core,candidate.center,candidate.roads.segments,0,assets)
  fitting_usec+=Time.get_ticks_usec()-begun
  if not lots.ok:continue
  var plan:Dictionary={"ok":true,"center":candidate.center,"roads":candidate.roads.segments,"lots":lots.lots,"mean_earthwork":candidate.roads.mean_earthwork}
  var works:Dictionary=Planner.earthworks(plan)
  if works.ok and Planner.footprint_clear(works.bounds,reserved):
   print("MARKET_PLAN_TIMINGS candidates=",candidates.size()," attempts=",attempts," survey_ms=",survey_usec/1000.0," recipe_ms=",recipe_usec/1000.0," fitting_ms=",fitting_usec/1000.0)
   return plan
 return {"ok":false,"reason":"No eight-building market fits the reserved landscape","candidates":candidates.size()}
