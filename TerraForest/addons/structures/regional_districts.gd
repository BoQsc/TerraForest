# SPDX-License-Identifier: 0BSD
extends RefCounted
# Offline composition choices; native prefabs own geometry and runtime batching.
static func plan(site:int)->Dictionary:
 var cottage:="Furnished cottage with door and windows"
 var tower:="Furnished tower · 3 floors"
 match site:
  1:return {"title":"Western residential lane","sources":[cottage],"lots":2,"streets":1,"width":6,"gap":4,"buildings":4}
  2:return {"title":"Eastern mine service street","sources":["Mine workshop and stores"],"lots":1,"streets":1,"width":8,"gap":4,"buildings":2}
  # Legacy composition metadata retained for its regression fixture. Production
  # district preparation uses northern_lots.gd and independently surveyed grades.
  3:return {"title":"Northern multi-storey district","sources":[tower],"lots":3,"streets":2,"width":10,"gap":5,"buildings":12}
  4:return {"title":"Southern homes and workshop lane","sources":[cottage,"Mine workshop and stores"],"lots":2,"streets":1,"width":12,"gap":8,"buildings":4}
 return {}

# Choose only the building-layout seed; terrain identity remains the requested seed.
# Native counts inspect the same choices as composition without allocating meshes.
static func mixed_layout_seed(sources:Array[Resource],world_seed:int,lots:int=2,streets:int=2)->Dictionary:
 if sources.size()!=2 or world_seed<0 or world_seed>2147483647 or lots<1 or streets<1:return {"ok":false}
 var low:int=mini(sources[0].get_cell_count(),sources[1].get_cell_count())*(lots*streets*2)
 var high:int=maxi(sources[0].get_cell_count(),sources[1].get_cell_count())*(lots*streets*2)
 if low==high:return {"ok":false,"reason":"Mixed building sources must have distinct cell counts"}
 var planner:Resource=ClassDB.instantiate("NativeBlockPrefab")
 var candidates:Array[int]=[]
 for offset in 16:candidates.append(world_seed+offset)
 # Bounded fallback candidate; validate against the requested layout dimensions.
 candidates.append(1703)
 for candidate:int in candidates:
  var counts:Dictionary=planner.layout_counts(sources,lots,candidate,streets)
  if counts.get("ok",false) and counts.blocks>low and counts.blocks<high:
   return {"ok":true,"seed":candidate,"buildings":counts.buildings}
 return {"ok":false,"reason":"No valid mixed layout within bounded recipe choices"}
