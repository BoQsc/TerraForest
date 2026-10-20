# SPDX-License-Identifier: 0BSD
extends Node
# Bounded presentation queue; all density evaluation stays on the native worker.
var atlas:Node
var terrain:Node
var image:Image
var dirty:Dictionary={}
var pending:Dictionary={}
var serial:=0
var patches:=0
var max_native_ms:=0.0
var epoch:=-1
func _ready()->void:
 terrain=atlas.game.terrain
 terrain.region_changed.connect(changed)
 terrain.survey_patch_ready.connect(receive)
 set_process(false)
func reset()->void:
 epoch=terrain.epoch;image=null;dirty.clear();pending.clear()
 for cell:Vector2i in terrain.modified_columns:
  changed(AABB(Vector3(cell.x*16,0,cell.y*16),Vector3(16,256,16)),0)
func changed(bounds:AABB,_revision:int)->void:
 var low:=Vector2i(floori((bounds.position.x-8)*256/2000/4),floori((bounds.position.z-8)*256/2000/4)).clamp(Vector2i.ZERO,Vector2i(63,63))
 var high:=Vector2i(floori((bounds.end.x+8)*256/2000/4),floori((bounds.end.z+8)*256/2000/4)).clamp(Vector2i.ZERO,Vector2i(63,63))
 for z in range(low.y,high.y+1):
  for x in range(low.x,high.x+1):dirty[Vector2i(x,z)]=true
func _process(_delta:float)->void:
 if not atlas.opened or image==null or not pending.is_empty() or dirty.is_empty():return
 if epoch!=terrain.epoch:return
 var tile:Vector2i=dirty.keys()[0]
 var rect:=Rect2i(tile*4,Vector2i(4,4));serial+=1
 if terrain.request_survey_patch(rect,serial):
  dirty.erase(tile);pending={"tile":tile,"token":serial}
func receive(result:Dictionary)->void:
 if pending.is_empty() or result.token!=pending.token:return
 var tile:Vector2i=pending.tile;pending.clear()
 if result.epoch!=epoch or terrain.epoch!=epoch:return
 if not result.get("ok",false) or result.get("revision",-1)!=terrain.density_revision or terrain.pending_edit:
  dirty[tile]=true;return
 if image==null:return
 var patch:=Image.create_from_data(4,4,false,Image.FORMAT_RGBA8,result.pixels)
 image.blit_rect(patch,Rect2i(0,0,4,4),tile*4)
 atlas.texture.update(image);patches+=1;max_native_ms=maxf(max_native_ms,result.generation_ms)
 atlas.view.queue_redraw()
 atlas.status.text=description()

func description()->String:
 var count:=dirty.size()+(0 if pending.is_empty() else 1)
 return "Terrain survey updating (%d areas) | Water: base survey"%count if count>0 else "Terrain surface surveyed | Water: base survey"
