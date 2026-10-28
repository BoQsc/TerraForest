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
 asset.set_meta("site_sample_band",5)
 # A bounded floor-level clearing fits inside the cellar shell. Site preparation
 # applies this after surface grading and before the combined prefab transaction.
 asset.set_meta("cellar_clearance",true)
 return asset

# Authored pedestrian connection from the western arterial around the cottage.
# Prepared before prefab placement so grading cannot cut through placed blocks.
static func connect_access(plan:Dictionary,site:Vector3)->Dictionary:
 if not plan.get("ok",false):return plan
 var points:=PackedVector3Array([site+Vector3(28,0,0),site+Vector3(28,0,29),site+Vector3(20.5,0,29),site+Vector3(20.5,0,28)])
 var lines:=PackedVector3Array()
 for i in range(points.size()-1):
  var a:=points[i];var b:=points[i+1]
  var bounds:=AABB(a.min(b)-Vector3(0.75,1,0.75),a.max(b)-a.min(b)+Vector3(1.5,5,1.5))
  if bounds.position.x<5 or bounds.position.z<5 or bounds.end.x>1995 or bounds.end.z>1995:return {"ok":false,"reason":"Cellar path outside world"}
  plan.segments.append({"start":a,"finish":b,"half_width":0.75,"depth":1.0,"clearance":4.0,"shoulder":0.0,"material":4,"bounds":bounds})
  plan.bounds=plan.bounds.merge(bounds)
  lines.append(a);lines.append(b)
 plan["street_lines"]=lines;plan["street_ends"]=PackedVector3Array([points[0],points[-1]])
 plan["street_width"]=1.5;plan["paving_segments"]=3
 return plan
