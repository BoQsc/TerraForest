# SPDX-License-Identifier: 0BSD
extends SceneTree
const Guide=preload("res://addons/player_runtime/destination_guide.gd")
func _initialize()->void:
 var failed:=0
 for row in [[Vector3(0,0,-100),"Ahead"],[Vector3(100,0,0),"Turn right"],[Vector3(-100,0,0),"Turn left"],[Vector3(0,0,100),"Behind you"]]:
  if Guide.guidance(Vector3.ZERO,Vector3.FORWARD,row[0]).direction!=row[1]:failed+=1
 if Guide.guidance(Vector3.ZERO,Vector3.RIGHT,Vector3(100,0,0)).direction!="Ahead":failed+=1
 if Guide.guidance(Vector3.ZERO,Vector3.FORWARD,Vector3(0,30,0)).arrived:failed+=1
 if not Guide.guidance(Vector3.ZERO,Vector3.FORWARD,Vector3(1,0,2)).arrived:failed+=1
 print("DESTINATION_GUIDE failures=",failed);quit(1 if failed else 0)
