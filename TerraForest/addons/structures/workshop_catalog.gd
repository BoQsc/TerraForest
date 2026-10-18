# SPDX-License-Identifier: 0BSD
extends RefCounted
# Offline authoring. Runtime geometry, collision and attachments use native batches.
static func workshop()->Resource:
 var cells:Dictionary={}
 for x in range(-6,7):
  for z in range(-8,9):
   cells[Vector3i(x,0,z)]=65
   cells[Vector3i(x,6,z)]=97
   for y in range(1,6):
    var wall:bool=abs(x)==6 or abs(z)==8
    var door:bool=z==8 and x==0 and y<=2
    var window:bool=y in [2,3] and ((abs(x)==6 and z in [-5,-4,3,4]) or (z==8 and x in [-4,-3,3,4]))
    if wall and not door and not window:cells[Vector3i(x,y,z)]=1
   # Rear stores partition: a three-metre-wide opening keeps circulation clear.
   if z==-2 and abs(x)>1:
    for y in range(1,6):cells[Vector3i(x,y,z)]=33
 # Ground-to-floor approach, using the same outward stair orientation as towers.
 for x in range(-1,2):cells[Vector3i(x,0,9)]=83
 var records:=PackedInt32Array()
 for cell:Vector3i in cells:records.append_array(PackedInt32Array([cell.x,cell.y,cell.z,cells[cell]]))
 var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
 if not asset.configure(records):return null
 var models:Array=[{"model":"architecture/wooden_door/v1","transform":Transform3D(Basis.IDENTITY.scaled(Vector3(1,0.9,1)),Vector3(0,1,8.5))}]
 for x in [-3.0,4.0]:
  models.append({"model":"architecture/wooden_window/v1","transform":Transform3D(Basis.IDENTITY,Vector3(x,2,8.5))})
 for x in [-5.5,6.5]:
  for z in [-4.0,4.0]:
   models.append({"model":"architecture/wooden_window/v1","transform":Transform3D(Basis(Vector3.UP,PI/2),Vector3(x,2,z))})
 for x in [-3.5,3.5]:
  for z in [1.0,4.0]:
   models.append({"model":"furniture/table/v1","transform":Transform3D(Basis.IDENTITY,Vector3(x,1,z))})
  models.append({"model":"furniture/shelf/v1","transform":Transform3D(Basis.IDENTITY,Vector3(x,1,-6.5))})
  models.append({"model":"storage/wooden_chest/v1","transform":Transform3D(Basis.IDENTITY,Vector3(x,1,-4))})
 if not asset.configure_model_attachments(models):return null
 asset.resource_name="Mine workshop and stores"
 return asset
