# SPDX-License-Identifier: 0BSD
extends SceneTree
const Locations=preload("res://demo/world_locations.gd")
func _initialize()->void:
 var places:=Locations.describe(1703,12)
 assert(places.size()==10)
 assert(places[5].title=="Eastern mine entrance")
 assert(places[6].title=="Large lake shore")
 var unique:Dictionary={}
 for place:Dictionary in places:
  assert(place.position.is_finite() and place.position.x>0 and place.position.z>0 and place.position.x<2000 and place.position.z<2000)
  assert(not unique.has(place.title));unique[place.title]=true
 assert(Locations.describe(1703,1).is_empty())
 print("WORLD_DESTINATIONS passed")
 quit()
