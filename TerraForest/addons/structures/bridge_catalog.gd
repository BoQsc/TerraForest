# SPDX-License-Identifier: 0BSD
extends RefCounted
# One-time authoring; all runtime geometry/storage uses NativeBlockWorld.
static func footbridge() -> Resource:
 var records:=PackedInt32Array()
 for x in range(-2,2):
  for z in 12:records.append_array(PackedInt32Array([x,0,z,33]))
  records.append_array(PackedInt32Array([x,0,-1,35,x,0,12,51]))
 for x in [-2,1]:
  for z in 12:
   records.append_array(PackedInt32Array([x,2,z,34]))
   if z%2==0:records.append_array(PackedInt32Array([x,1,z,37]))
 var asset: Resource=ClassDB.instantiate("NativeBlockPrefab")
 if not asset.configure(records):return null
 asset.resource_name="Timber footbridge · 12 m span"
 return asset
