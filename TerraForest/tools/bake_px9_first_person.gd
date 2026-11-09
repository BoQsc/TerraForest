# SPDX-License-Identifier: 0BSD
extends "res://tools/bake_first_person_meshes.gd"
func run()->void:
 var model:Node3D=load(MODEL_PATH).instantiate();root.add_child(model)
 var body:MeshInstance3D=model.find_child("Human_Body",true,false)
 var skeleton:Skeleton3D=model.find_children("*","Skeleton3D",true,false)[0]
 var mesh:ArrayMesh=load("res://addons/characters/runtime/px9/Human.px9_eclipse.body.res")
 for arms in [false,true]:
  var result:=split_mesh(mesh,body.skin,skeleton,arms)
  var path:="res://addons/characters/runtime/px9/first_person_"+("arms" if arms else "body")+".res"
  if ResourceSaver.save(result,path)!=OK:quit(1);return
 model.free();quit()
