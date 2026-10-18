# SPDX-License-Identifier: 0BSD
extends RefCounted
# Infrequent prefab authoring. Runtime blocks, attachments and terrain stay native.
static func cottage() -> Resource:
 var source:Resource=preload("res://addons/structures/furniture_catalog.gd").enclosed_cottage()
 if source==null:return null
 var cells:Dictionary={}
 var records:PackedInt32Array=source.get_records()
 for i in range(0,records.size(),4):
  var cell:=Vector3i(records[i],records[i+1],records[i+2])
  # Two-metre hatch through both foundation and ground floor, away from furniture.
  if cell.x in [1,2] and cell.z in [2,3] and cell.y in [0,1]:continue
  cells[cell]=records[i+3]
 for x in range(-3,4):
  for z in range(-4,5):
   cells[Vector3i(x,-5,z)]=65
   for y in range(-4,0):
    if x in [-3,3] or z in [-4,4]:cells[Vector3i(x,y,z)]=65
 records=PackedInt32Array()
 for cell:Vector3i in cells:records.append_array(PackedInt32Array([cell.x,cell.y+5,cell.z,cells[cell]]))
 var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
 if not asset.configure(records):return null
 var models:Array=source.get_model_attachments()
 for model:Dictionary in models:
  var pose:Transform3D=model.transform;pose.origin.y+=5;model.transform=pose
 models.append({"model":"architecture/wooden_ladder/v1","transform":Transform3D(Basis.IDENTITY.scaled(Vector3(1,1.7,1)),Vector3(1.5,1,2.5))})
 models.append({"model":"storage/wooden_chest/v1","transform":Transform3D(Basis.IDENTITY,Vector3(-1,1,-2))})
 if not asset.configure_model_attachments(models):return null
 asset.resource_name="Cottage with cellar"
 asset.set_meta("site_surface_offset",5)
 # A bounded floor-level clearing fits inside the cellar shell. Site preparation
 # applies this after surface grading and before the combined prefab transaction.
 asset.set_meta("cellar_clearance",true)
 return asset
