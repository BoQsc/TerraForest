# SPDX-License-Identifier: 0BSD
extends RefCounted
const PATH:="res://vehicle_demo/assets/Vehicle.parked.res"
const RECEIPT:="res://vehicle_demo/assets/Vehicle.parked.bake.json"
static var mesh:Mesh
static var checked:=false
static var current:=false
static func valid_receipt(receipt:Variant)->bool:
	if not FileAccess.file_exists(PATH):return false
	if not receipt is Dictionary or receipt.get("schema")!=1 or not receipt.get("sources") is Dictionary or receipt.sources.is_empty() or receipt.sources.size()>64:return false
	if not receipt.get("output_sha256") is String or receipt.output_sha256.length()!=64 or receipt.output_sha256!=FileAccess.get_sha256(PATH):return false
	for path:Variant in receipt.sources:
		if not path is String or not path.begins_with("res://") or not receipt.sources[path] is String or receipt.sources[path].length()!=64:return false
		if path.ends_with(".import") and not FileAccess.file_exists(path.trim_suffix(".import")):continue
		if FileAccess.file_exists(path) and FileAccess.get_sha256(path)!=receipt.sources[path]:return false
	return true
static func parts(original:Array)->Array:
	if not checked:
		checked=true
		var receipt:Variant=JSON.parse_string(FileAccess.get_file_as_string(RECEIPT)) if FileAccess.file_exists(RECEIPT) else null
		current=valid_receipt(receipt)
		if current:mesh=load(PATH) as Mesh
	if not current or mesh==null or original.size()!=32:return original
	return [{"mesh":mesh,"transform":Transform3D.IDENTITY,"material":null}]
