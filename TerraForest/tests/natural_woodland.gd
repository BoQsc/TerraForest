# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 var scatter=ClassDB.instantiate("NativeVegetationScatter")
 var quadrants:=[0,0,0,0];var empty:=0;var full:=0;var ok:=true
 for z in 32:
  for x in 32:
   var cell:=Vector2i(x,z)
   var a:Dictionary=scatter.candidates(cell,42,0.82,true)
   var b:Dictionary=scatter.candidates(cell,42,0.82,true)
   ok=ok and a==b and a.ids.size()<=36
   quadrants[(1 if x>=16 else 0)+(2 if z>=16 else 0)]+=a.ids.size()
   if a.ids.is_empty():empty+=1
   if a.ids.size()>=20:full+=1
 for count:int in quadrants:ok=ok and count>100
 ok=ok and empty>0 and full>0
 print("WOODLAND quadrants=",quadrants," clear_owners=",empty," wooded_owners=",full)
 print("NATURAL_WOODLAND failures=",0 if ok else 1);quit(0 if ok else 1)
