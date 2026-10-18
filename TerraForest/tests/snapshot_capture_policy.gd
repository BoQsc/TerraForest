# SPDX-License-Identifier: 0BSD
extends SceneTree
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
class DummyCodec extends RefCounted:
 func release()->void:pass
var captures:=0
func capture()->Dictionary:
 captures+=1
 return {"epoch":0,"sections":{}}
func _initialize()->void:
 var backend=Backend.new()
 backend.snapshot_codec=DummyCodec.new()
 backend.snapshot_capture=capture
 backend.temporary=true
 assert(backend.submit({"kind":"save"}))
 assert(captures==0)
 backend.stop()
 assert(captures==0)
 backend=Backend.new()
 backend.snapshot_codec=DummyCodec.new()
 backend.snapshot_capture=capture
 assert(backend.submit({"kind":"save"}))
 assert(captures==1)
 backend.stop()
 assert(captures==2)
 backend=Backend.new()
 backend.snapshot_codec=DummyCodec.new()
 backend.snapshot_capture=capture
 backend.disable_snapshot_writes("test read-only policy")
 assert(backend.submit({"kind":"save"}))
 backend.stop()
 assert(captures==2)
 print("SNAPSHOT_CAPTURE_POLICY passed")
 quit()
