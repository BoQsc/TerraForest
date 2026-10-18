# SPDX-License-Identifier: 0BSD
extends SceneTree
class Terrain extends Node:
 signal surface_batch_ready(token,points,normals,epoch,revision)
 func request_surface_batch(points:PackedVector3Array,token:int)->bool:
  var normals:=PackedVector3Array();normals.resize(points.size());normals.fill(Vector3.UP)
  surface_batch_ready.emit.call_deferred(token,points,normals,1,0)
  return true
class Exclusion extends RefCounted:
 func overlap_mask(poses:Array[Transform3D],_box:AABB)->PackedByteArray:
  var result:=PackedByteArray();result.resize(poses.size());return result
 func placement_mask(poses:Array[Transform3D])->PackedByteArray:return overlap_mask(poses,AABB())
class Cover extends RefCounted:
 var removed:RefCounted
 var resident:Dictionary={Vector2i(31,31):[],Vector2i(32,31):[]}
 var _dirty:Dictionary={}
class Game extends Node:
 var terrain:Node
 var ground_cover:RefCounted
 var structures:RefCounted
 var lakes:RefCounted
func _initialize()->void:run.call_deferred()
func run()->void:
 GDExtensionManager.load_extension("res://addons/vegetation_runtime/vegetation_runtime.gdextension")
 var game:=Game.new();root.add_child(game);game.terrain=Terrain.new();game.add_child(game.terrain)
 game.ground_cover=Cover.new();game.ground_cover.removed=ClassDB.instantiate("NativeGroundCoverState");game.ground_cover.removed.bind_world(1703,1)
 game.structures=Exclusion.new();game.lakes=Exclusion.new()
 for i in 256:game.ground_cover.removed.add(2,Transform3D(Basis.IDENTITY,Vector3(1025,20,1020)))
 var before:PackedByteArray=game.ground_cover.removed.capture_storage_snapshot()
 var result:Dictionary=await preload("res://addons/world_ecosystem/woodland_authoring.gd").plant(game,Vector3(1024,20,1024),1703,24)
 var ok:bool=not result.ok and result.reason=="Woodland authored capacity exceeded" and game.ground_cover.removed.capture_storage_snapshot()==before and game.ground_cover._dirty.size()==2
 print("PASS capacity failure rolls back partial planting and invalidates publication" if ok else "FAIL rollback")
 var success:Dictionary=await preload("res://addons/world_ecosystem/woodland_authoring.gd").plant(game,Vector3(970,20,970),1703,8)
 ok=ok and success.ok and game.ground_cover.removed.profile().placed>256
 game.free();print("WOODLAND_ATOMIC failures=",0 if ok else 1);quit(0 if ok else 1)
