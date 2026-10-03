# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var codec: RefCounted=ClassDB.instantiate("NativePlayerPose")
	var data: PackedByteArray=codec.encode(Vector3(800,50,1200),0.4,-0.2,false,3)
	var decoded: Dictionary=codec.decode(data)
	check(data.size()==56 and decoded.ok and decoded.position==Vector3(800,50,1200) and decoded.tool==3 and not decoded.fly,"native player pose roundtrip")
	check(codec.validate_snapshot(PackedByteArray()) and not codec.decode(PackedByteArray()).has("position"),"legacy empty pose requests default spawn")
	for offset in [8,16,24,32,40]:
		var bad:=data.duplicate();bad.encode_double(offset,NAN)
		check(not codec.validate_snapshot(bad),"nonfinite pose field rejected at %d"%offset)
	for offset in [0,4,48,52]:
		var bad:=data.duplicate();bad.encode_u32(offset,0xffffffff)
		check(not codec.validate_snapshot(bad),"invalid header or mode rejected at %d"%offset)
	check(not codec.validate_snapshot(data.slice(0,55)),"truncated pose rejected")
	check(codec.encode(Vector3(2500,100,2500),0,0,false,1).is_empty(),"walking pose outside playable bounds rejected")
	check(not codec.encode(Vector3(2500,100,2500),0,0,true,1).is_empty(),"flight bounds admit overview position")
	check(codec.encode(Vector3(800,50,1200),0,2,false,1).is_empty(),"invalid pitch rejected")
	quit(1 if failures else 0)
