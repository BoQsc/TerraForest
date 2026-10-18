# SPDX-License-Identifier: 0BSD
extends RefCounted
# Offline composition choices; native prefabs own geometry and runtime batching.
static func plan(site:int)->Dictionary:
 var cottage:="Furnished cottage with door and windows"
 var tower:="Furnished tower · 3 floors"
 match site:
  1:return {"title":"Western residential lane","sources":[cottage],"lots":2,"streets":1,"width":6,"gap":4,"buildings":4}
  2:return {"title":"Eastern mine service street","sources":["Mine workshop and stores"],"lots":1,"streets":1,"width":8,"gap":4,"buildings":2}
  3:return {"title":"Northern multi-storey district","sources":[tower],"lots":2,"streets":1,"width":10,"gap":5,"buildings":4}
  4:return {"title":"Southern broad residential lane","sources":[cottage],"lots":2,"streets":1,"width":12,"gap":8,"buildings":4}
 return {}

# Choose only the building-layout seed; terrain identity remains the requested seed.
# Native counts inspect the same choices as composition without allocating meshes.
static func mixed_layout_seed(sources:Array[Resource],world_seed:int)->Dictionary:
 if sources.size()!=2 or world_seed<0 or world_seed>2147483647:return {"ok":false}
 var low:int=mini(sources[0].get_cell_count(),sources[1].get_cell_count())*8
 var high:int=maxi(sources[0].get_cell_count(),sources[1].get_cell_count())*8
 if low==high:return {"ok":false,"reason":"Mixed building sources must have distinct cell counts"}
 var planner:Resource=ClassDB.instantiate("NativeBlockPrefab")
 var candidates:Array[int]=[]
 for offset in 16:candidates.append(world_seed+offset)
 # Verified fallback for this two-source, eight-building recipe; still validate.
 candidates.append(1703)
 for candidate:int in candidates:
  var counts:Dictionary=planner.layout_counts(sources,2,candidate,2)
  if counts.get("ok",false) and counts.blocks>low and counts.blocks<high:
   return {"ok":true,"seed":candidate,"buildings":counts.buildings}
 return {"ok":false,"reason":"No valid mixed layout within bounded recipe choices"}
