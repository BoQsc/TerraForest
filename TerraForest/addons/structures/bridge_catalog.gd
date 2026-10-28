# SPDX-License-Identifier: 0BSD
extends RefCounted
# One-time authoring; all runtime geometry/storage uses NativeBlockWorld.
static func footbridge(metal_rails: bool=false) -> Resource:
 var records:=PackedInt32Array()
 for x in range(-2,2):
  for z in 12:records.append_array(PackedInt32Array([x,0,z,33]))
  records.append_array(PackedInt32Array([x,0,-1,35,x,0,12,51]))
 for x in ([] if metal_rails else [-2,1]):
  for z in 12:
   records.append_array(PackedInt32Array([x,2,z,34]))
   if z%2==0:records.append_array(PackedInt32Array([x,1,z,37]))
 var asset: Resource=ClassDB.instantiate("NativeBlockPrefab")
 if not asset.configure(records):return null
 if metal_rails:
  var attachments: Array=[]
  for x in [-2.0,2.0]:
   for z in [2,6,10]:attachments.append({"model":"architecture/metal_guardrail/v1","transform":Transform3D(Basis.IDENTITY,Vector3(x,1,z))})
  # Include a centimetre of clearance for rotated, translated proxy bounds.
  if not asset.configure_model_attachments(attachments) or not asset.configure_attachment_envelope(AABB(Vector3(-2.07,0,-1),Vector3(4.14,2.11,14))):return null
  asset.resource_name="Timber footbridge with metal rails - 12 m span"
  return asset
 asset.resource_name="Timber footbridge · 12 m span"
 return asset

static func lake_crossing(span:int)->Resource:
 if span<24 or span>44 or span%2!=0:return null
 var records:=PackedInt32Array()
 for along in span:
  for across in 6:records.append_array(PackedInt32Array([across,0,along,33 if across in [0,5] else 160]))
  if along not in [0,span-1]:
   for across in [1,4]:records.append_array(PackedInt32Array([across,-1,along,33]))
  for across in [0,5]:
   records.append_array(PackedInt32Array([across,2,along,34]))
   if along%3==0 or along==span-1:records.append_array(PackedInt32Array([across,1,along,37]))
 for along in [0,span-1]:
  for across in 6:records.append_array(PackedInt32Array([across,-1,along,65]))
 var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
 if not asset.configure(records):return null
 asset.resource_name="Timber lake crossing · %d m span"%span
 return asset
