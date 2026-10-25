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

# Village service building: shares the workshop footprint/entrance contract, but
# has its own roof silhouette and sales/storage circulation. Offline recipe only.
static func village_shop()->Resource:
 var source:Resource=workshop()
 if source==null:return null
 var cells:Dictionary={}
 var original:PackedInt32Array=source.get_records()
 for i in range(0,original.size(),4):
  var p:=Vector3i(original[i],original[i+1],original[i+2])
  if p.y==6:continue
  cells[p]=original[i+3]
 # Sloped timber roof, ridge along the long axis. Gables close both ends;
 # every roof column stays within the surveyed workshop footprint.
 for x in range(-6,7):
  var roof_y:int=6+6-absi(x)
  for z in range(-8,9):
   cells[Vector3i(x,roof_y,z)]=33 if x==0 else (60 if x<0 else 44)
   if absi(z)==8:
    for y in range(6,roof_y):cells[Vector3i(x,y,z)]=1
 var records:=PackedInt32Array()
 for p:Vector3i in cells:records.append_array(PackedInt32Array([p.x,p.y,p.z,cells[p]]))
 var shop:Resource=ClassDB.instantiate("NativeBlockPrefab")
 if not shop.configure(records):return null
 var models:Array=[]
 for entry:Dictionary in source.get_model_attachments():
  if entry.model=="furniture/table/v1":continue
  models.append(entry)
 # Two counters leave a central customer route and access to the rear stores.
 for x in [-3.5,3.5]:
  models.append({"model":"furniture/table/v1","transform":Transform3D(Basis.IDENTITY,Vector3(x,1,0.5))})
  models.append({"model":"furniture/shelf/v1","transform":Transform3D(Basis.IDENTITY,Vector3(x,1,-0.8))})
 if not shop.configure_model_attachments(models):return null
 shop.resource_name="Village general store"
 return shop

static func hipped_shop()->Resource:
 return load("res://addons/structures/prefabs/village_shop_hipped_r1.tres")
