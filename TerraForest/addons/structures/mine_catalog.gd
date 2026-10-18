# SPDX-License-Identifier: 0BSD
extends RefCounted
# Offline prefab authoring only; native block batches own runtime rendering/collision.
# Local +X is outside, -X enters the mine. Keep the central walkway unobstructed.
static func entrance() -> Resource:
 var records:=PackedInt32Array()
 for x in [0,4]:
  for z in [-5,5]:
   for y in range(0,8):records.append_array(PackedInt32Array([x,y,z,33]))
  for z in range(-4,5):records.append_array(PackedInt32Array([x,7,z,33]))
 # Side timber stack marks the work yard without blocking the entrance.
 for x in range(7,11):
  for z in range(7,10):
   for y in 2:records.append_array(PackedInt32Array([x,y,z,33]))
 var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
 if not asset.configure(records):return null
 if not asset.configure_model_attachments([
  {"model":"storage/wooden_chest/v1","transform":Transform3D(Basis.IDENTITY,Vector3(7,0,4))}
 ]):return null
 asset.resource_name="Mine entrance and supply yard"
 return asset
