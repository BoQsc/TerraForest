# SPDX-License-Identifier: 0BSD
extends Node3D
# Main-thread presentation only. Finite compilation/sampling runs on terrain worker.
signal catalog_changed
signal lake_ready(id: int)
signal lake_failed(id: int,status: int)
signal exclusion_changed(bounds: AABB)
@export var terrain: Node3D
@export_range(1,16) var max_lakes: int=8
var _lakes: Dictionary={}
var _next_id:=1
var _token:=0
var _busy_id:=0
var _epoch:=-1
var _catalog: RefCounted
var _material:=ShaderMaterial.new()
var _discard_completion:=false
var _surface_cursor:=0
func prepare() -> bool:
 if not ClassDB.class_exists("NativeWaterRuntime"):GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
 if not ClassDB.class_exists("NativeWaterRuntime"):return false
 if _catalog==null:_catalog=ClassDB.instantiate("NativeLakeCatalog")
 return true
func snapshot_validator() -> RefCounted:return _catalog
func empty_snapshot() -> PackedByteArray:return _catalog.encode([])
func capture_snapshot() -> PackedByteArray:
 var records:Array=[]
 var ids:=_lakes.keys();ids.sort()
 for id:int in ids:
  var item:Dictionary=_lakes[id]
  if item.volume!=null:item.water_state=item.volume.capture_state()
  records.append({"id":id,"origin":item.origin,"cells":item.cells,"spacing":item.spacing,"level":item.level,"seed":item.seed,"water_state":item.water_state})
 return _catalog.encode(records,_next_id)
func restore_snapshot(bytes:PackedByteArray) -> bool:
 var decoded:Dictionary=_catalog.decode(bytes)
 if not decoded.get("ok",false):return false
 clear();_next_id=decoded.next_id;max_lakes=maxi(max_lakes,decoded.records.size())
 for record:Dictionary in decoded.records:_install(record)
 return true
func _ready() -> void:
 if terrain==null or transform!=Transform3D.IDENTITY or global_transform!=Transform3D.IDENTITY or not prepare():set_process(false);return
 _material.shader=preload("res://addons/volumetric_water/water.gdshader")
 terrain.lake_slice_ready.connect(_slice_ready);terrain.region_invalidated.connect(_invalidate)
 terrain.water_edit_admission=allows_edit
 _epoch=terrain.epoch
func add_lake(origin:Vector3,cells:Vector3i,spacing:float,level:float,seed:Vector3) -> int:
 if _catalog==null or _lakes.size()>=mini(max_lakes,16):return 0
 var definition:Dictionary={"id":_next_id,"origin":origin,"cells":cells,"spacing":spacing,"level":level,"seed":seed}
 if _catalog.encode([definition]).is_empty():return 0
 var bounds:=owned_bounds(definition)
 for item:Dictionary in _lakes.values():
  if item.owned_bounds.intersects(bounds):return 0
 var builder=ClassDB.instantiate("NativeWaterRuntime")
 if not builder.configure(origin,cells,spacing,level,seed,PackedByteArray()):return 0
 _next_id+=1;_install(definition);return definition.id
func _install(record:Dictionary) -> void:
 var item:=record.duplicate()
 item.bounds=AABB(item.origin,Vector3(item.cells)*item.spacing)
 item.owned_bounds=owned_bounds(item)
 item.water_state=item.get("water_state",PackedByteArray());item.volume=null;item.builder=null
 item.dirty=true;item.revision=-1;item.failure="";item.scene=ClassDB.instantiate("NativeWaterScene")
 add_child(item.scene);item.scene.set_keep_previous_surface(true);item.scene.set_process(false)
 for existing:Dictionary in _lakes.values():
  if existing.owned_bounds.intersects(item.owned_bounds):
   existing.dirty=false;item.dirty=false
   existing.failure="Overlapping finite lake regions; remove one definition before retrying";item.failure=existing.failure
 _lakes[item.id]=item;catalog_changed.emit()
func remove_lake(id:int) -> void:
 if not _lakes.has(id):return
 if id==_busy_id:_discard_completion=true
 var item:Dictionary=_lakes[id];item.scene.queue_free();_lakes.erase(id)
 if is_instance_valid(terrain):terrain.changed_since_save=true
 catalog_changed.emit();exclusion_changed.emit(item.bounds)
func clear() -> void:
 for id:int in _lakes.keys():remove_lake(id)
func owned_bounds(item:Dictionary) -> AABB:
 var size:float=16.0*item.spacing
 var lo:Vector3=(item.origin/size).floor()*size
 var hi:Vector3=((item.origin+Vector3(item.cells)*item.spacing)/size).ceil()*size
 hi.y=minf(hi.y,(floorf(item.level/size)+1)*size)
 return AABB(lo,hi-lo)
func allows_edit(bounds:AABB) -> bool:
 for item:Dictionary in _lakes.values():
  # Include sampling halo and complete owned regions, not just authored bounds.
  if (item.volume!=null or not item.water_state.is_empty()) and item.owned_bounds.grow(item.spacing).intersects(bounds):
   terrain.message_changed.emit("Finite lake protected: remove its water in Development > Water before reshaping this basin.");return false
 return true
func _invalidate(bounds:AABB) -> void:
 for item:Dictionary in _lakes.values():
  if item.bounds.intersects(bounds) and item.volume==null:item.builder=null;item.dirty=true
func _process(_delta:float) -> void:
 if not is_instance_valid(terrain):return
 if _epoch!=terrain.epoch:_epoch=terrain.epoch
 var ids:=_lakes.keys()
 for index in ids.size():
  _surface_cursor=(_surface_cursor+1)%ids.size()
  var item:Dictionary=_lakes[ids[_surface_cursor]]
  var state:Dictionary=item.scene.statistics()
  if item.volume!=null and not state.ready and state.status!=0 and not state.retiring:
   item.scene.begin_publish(item.volume,_material);item.scene.set_process(false);state=item.scene.statistics()
  if state.status==0 or state.retiring:
   item.scene.advance(2048);break # Shared soft 2ms budget / at most one regional upload.
 if _busy_id!=0 or not terrain.world_ready or terrain.pending_edit:return
 for id:int in _lakes:
  var item:Dictionary=_lakes[id]
  if not item.dirty:continue
  if item.builder==null or item.revision!=terrain.published_revision:
   item.builder=ClassDB.instantiate("NativeWaterRuntime")
   if not item.builder.configure(item.origin,item.cells,item.spacing,item.level,item.seed,item.water_state):
    item.failure="Lake exceeds finite water bounds";item.builder=null;item.dirty=false;catalog_changed.emit();lake_failed.emit(id,-2);return
   item.revision=terrain.published_revision
  _token=item.builder.get_instance_id()
  if terrain.request_lake_slice(item.builder,_token):_busy_id=id
  return
func _slice_ready(token:int,status:int,epoch_id:int,revision:int) -> void:
 if token!=_token or _busy_id==0:return
 var id:=_busy_id;_busy_id=0
 if _discard_completion:_discard_completion=false;return
 if not _lakes.has(id):return
 var item:Dictionary=_lakes[id]
 if item.builder==null or epoch_id!=terrain.epoch or revision!=terrain.published_revision or terrain.pending_edit or status==-4:item.builder=null;return
 if status==0:return
 item.dirty=false
 if status!=1:
  item.failure=item.builder.statistics().error;item.builder=null;catalog_changed.emit();lake_failed.emit(id,status);return
 item.volume=item.builder.get_network();item.water_state=item.volume.capture_state();item.builder=null
 item.scene.begin_publish(item.volume,_material);item.scene.set_process(false)
 catalog_changed.emit();lake_ready.emit(id);exclusion_changed.emit(item.bounds)
func placement_mask(transforms:Array[Transform3D]) -> PackedByteArray:
 var volumes:Array=[]
 for item:Dictionary in _lakes.values():
  if item.volume!=null:volumes.append(item.volume)
 return _catalog.placement_mask(volumes,transforms) if _catalog!=null else PackedByteArray()
func depth_at(point:Vector3) -> float:
 var depth:=0.0
 for item:Dictionary in _lakes.values():
  if item.volume!=null:depth=maxf(depth,float(item.volume.probe(point).get("depth_m",0.0)))
 return depth
func bucket(from:Vector3,to:Vector3,pour:bool,inventory:RefCounted,slot:int,revision:int) -> Dictionary:
 if not terrain.world_ready or terrain.pending_edit:return {"ok":false,"reason":"Wait for terrain to finish loading"}
 for item:Dictionary in _lakes.values():
  if item.volume==null:continue
  var hit:Dictionary=item.volume.ray_probe(from,to,not pour)
  if hit.is_empty():continue
  if not item.volume.transfer_litre(hit.point,pour,inventory,slot,revision):return {"ok":false,"reason":"Bucket full / empty, or less than one litre can be transferred"}
  item.scene.refresh();item.scene.begin_publish(item.volume,_material);item.scene.set_process(false)
  item.water_state=item.volume.capture_state();terrain.changed_since_save=true
  exclusion_changed.emit(item.bounds);catalog_changed.emit()
  return {"ok":true,"reason":"Poured 1 L" if pour else "Scooped 1 L"}
 return {"ok":false,"reason":"Aim within reach at water or inside an existing lake basin"}
func statistics() -> Dictionary:
 var ready:=0;var amount:=0
 for item:Dictionary in _lakes.values():
  if item.volume!=null:ready+=1;amount+=int(item.volume.statistics().owned_ml)
 return {"lakes":_lakes.size(),"ready":ready,"resident_occupancy_bytes":0,"outstanding_slices":int(_busy_id!=0),"water_ml":amount}
func descriptions() -> Array[Dictionary]:
 var rows:Array[Dictionary]=[]
 for id:int in _lakes:
  var item:Dictionary=_lakes[id]
  rows.append({"id":id,"state":"Baking" if item.dirty else "Ready" if item.volume!=null else "Failed","reason":item.failure,"level":item.level,"origin":item.origin})
 return rows
func retry_lake(id:int) -> bool:
 if not _lakes.has(id) or _lakes[id].dirty:return false
 for other:int in _lakes:
  if other!=id and _lakes[other].owned_bounds.intersects(_lakes[id].owned_bounds):return false
 _lakes[id].builder=null;_lakes[id].dirty=true;_lakes[id].failure="";catalog_changed.emit();return true
