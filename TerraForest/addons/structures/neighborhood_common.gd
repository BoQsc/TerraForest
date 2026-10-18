# SPDX-License-Identifier: 0BSD
extends RefCounted
# Offline authoring recipe. Blocks, attached props, interactions and storage all
# use the existing native collections; no runtime controller or per-prop nodes.
static func build(center:Vector3)->Dictionary:
 var occupied:Dictionary={}
 for x in range(-8,-6):
  for z in range(4,48):occupied[Vector3i(x,0,z)]=65
 for start_z in [9,34]:
  for x in range(-14,-8):
   for z in range(start_z,start_z+8):occupied[Vector3i(x,0,z)]=65
 var records:=PackedInt32Array()
 for cell:Vector3i in occupied:records.append_array(PackedInt32Array([cell.x,cell.y,cell.z,occupied[cell]]))
 var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
 if not asset.configure(records):return {"ok":false,"reason":"Common paving rejected"}
 var models:Array=[]
 for z in [12.5,37.5]:
  models.append({"model":"furniture/table/v1","transform":Transform3D(Basis.IDENTITY,Vector3(-11,1,z))})
  models.append({"model":"furniture/chair/v1","transform":Transform3D(Basis.IDENTITY,Vector3(-11,1,z+1.3))})
  models.append({"model":"furniture/chair/v1","transform":Transform3D(Basis(Vector3.UP,PI),Vector3(-11,1,z-1.3))})
 models.append({"model":"storage/wooden_chest/v1","transform":Transform3D(Basis(Vector3.UP,PI/2),Vector3(-11,1,40.5))})
 if not asset.configure_model_attachments(models):return {"ok":false,"reason":"Common furniture rejected"}
 if not asset.configure_attachment_envelope(AABB(Vector3(-14,0,4),Vector3(8,2,44))):return {"ok":false,"reason":"Common model envelope rejected"}
 asset.resource_name="Northern common with public supplies"
 var paths:Array=[_bed(center+Vector3(-7,-0.1,5),center+Vector3(-7,-0.1,47))]
 for start_z in [9,34]:
  for x in [-13,-11,-9]:paths.append(_bed(center+Vector3(x,-0.1,start_z+1),center+Vector3(x,-0.1,start_z+7)))
 return {"ok":true,"asset":asset,"origin":Vector3i(center)-Vector3i.UP,"segments":paths,"supply_position":center+Vector3(-11,0,40.5),"route":PackedVector3Array([center+Vector3(-10,0,5),center+Vector3(-7,0,5),center+Vector3(-7,0,12.5),center+Vector3(-9,0,12.5),center+Vector3(-7,0,12.5),center+Vector3(-7,0,37.5),center+Vector3(-9,0,40.5),center+Vector3(-7,0,40.5),center+Vector3(-7,0,47),center+Vector3(-10,0,47)])}
static func _bed(a:Vector3,b:Vector3)->Dictionary:
 var low:=a.min(b)-Vector3(1,1,1);var high:=a.max(b)+Vector3(1,3,1)
 return {"start":a,"finish":b,"bounds":AABB(low,high-low),"half_width":1,"depth":1,"clearance":3,"material":1,"shoulder":0}
