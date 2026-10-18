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

static func access_plan(entrance:Vector3,site:Vector3)->Dictionary:
 var junction:=Vector3(entrance.x,entrance.y,site.z)
 var bend:=Vector3(entrance.x+14,entrance.y,site.z)
 var yard:=entrance+Vector3(14,0,0)
 var segments:Array[Dictionary]=[]
 var bounds:=AABB()
 var lines:=PackedVector3Array([junction,bend,bend,yard])
 for pair in [[junction,bend,3.0],[bend,yard,3.0],[entrance+Vector3(6,0,0),yard,6.0]]:
  var a:Vector3=pair[0];var b:Vector3=pair[1];var width:float=pair[2]
  var region:=AABB(a.min(b)-Vector3(width,8,width),a.max(b)-a.min(b)+Vector3(width*2,20,width*2))
  if region.position.x<5 or region.position.z<5 or region.end.x>1995 or region.end.z>1995:return {"ok":false}
  bounds=region if segments.is_empty() else bounds.merge(region)
  segments.append({"start":a,"finish":b,"half_width":width,"depth":8.0,"clearance":12.0,"material":4,"shoulder":0.0,"bounds":region})
 return {"ok":true,"bounds":bounds,"segments":segments,"street_lines":lines,"street_ends":lines.slice(0,2),"street_width":6,"paving_segments":2}
