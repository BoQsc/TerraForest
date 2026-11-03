# SPDX-License-Identifier: 0BSD
extends RefCounted
## One-time contents pass for existing town storage, saved with the world.
const LIMIT:=4096
const MAGIC:=0x32534c54
var visited:Dictionary={}
var complete:=false
var upper_identity:=0
var initialized:=false
var pending:=PackedInt64Array()
var cursor:=0
var started:=false
var towns:=PackedVector3Array()

func prepare(persistence:RefCounted)->bool:
	return persistence.register_component("town_scrap_v1",capture_snapshot,restore_snapshot,self,PackedByteArray())

func capture_snapshot()->PackedByteArray:
	var ids:Array=visited.keys();ids.sort()
	var bytes:=PackedByteArray();bytes.resize(20+ids.size()*8)
	bytes.encode_u32(0,MAGIC);bytes.encode_u32(4,int(complete)+int(initialized)*2);bytes.encode_u32(8,ids.size());bytes.encode_u64(12,upper_identity)
	for index in ids.size():bytes.encode_u64(20+index*8,ids[index])
	return bytes

func validate_snapshot(bytes:PackedByteArray)->bool:
	if bytes.is_empty():return true
	if bytes.size()<20 or bytes.decode_u32(0)!=MAGIC or bytes.decode_u32(4)>3:return false
	var count:=bytes.decode_u32(8)
	if count>LIMIT or bytes.size()!=20+count*8:return false
	var maximum:=bytes.decode_u64(12)
	if maximum<0 or ((bytes.decode_u32(4)&2)==0 and (maximum!=0 or count>0 or bytes.decode_u32(4)!=0)):return false
	var previous:=0
	for index in count:
		var identity:=bytes.decode_u64(20+index*8)
		if identity<=previous or identity>maximum:return false
		previous=identity
	return true

func restore_snapshot(bytes:PackedByteArray)->bool:
	if not validate_snapshot(bytes):return false
	visited.clear();complete=false;initialized=false;upper_identity=0;started=false;pending=PackedInt64Array();cursor=0;towns=PackedVector3Array()
	if bytes.is_empty():return true
	complete=(bytes.decode_u32(4)&1)!=0;initialized=(bytes.decode_u32(4)&2)!=0;upper_identity=bytes.decode_u64(12)
	for index in bytes.decode_u32(8):visited[bytes.decode_u64(20+index*8)]=true
	return true

func step(storage:Node)->bool:
	if complete or storage.game.terrain.backend.readonly_snapshot:return true
	var game:Node=storage.game
	if game.loading_active or game.shutdown_requested or not game.terrain.world_ready or game.terrain.pending_edit:return false
	if not started:
		towns.clear()
		for place:Dictionary in game.generated_region.store.get_plan().get("places",[]):
			if int(place.id)>=30 and int(place.id)<200:towns.append(place.position)
		if towns.is_empty():return false
		if not initialized:
			upper_identity=storage.collection.stats().last_identity;initialized=true;game.terrain.changed_since_save=true
		pending=storage.collection.get_ids()
		if pending.size()>LIMIT:return false
		started=true
	for work in 4:
		if cursor>=pending.size():
			complete=true;return true
		var identity:int=pending[cursor];cursor+=1
		if identity>upper_identity or visited.has(identity) or visited.size()>=LIMIT:continue
		var values:PackedFloat32Array=storage.collection.get_instance(identity)
		if values.size()!=12:continue
		var point:Vector3=storage.collection.to_global(Vector3(values[3],values[7],values[11]))
		var in_town:=false
		for town:Vector3 in towns:
			if Vector2(point.x-town.x,point.z-town.z).length_squared()<224*224:in_town=true;break
		if not in_town:continue
		if not storage.store.has_contents(identity):
			if not storage.store.seed_contents(identity,preload("res://addons/player_runtime/salvage_catalog.gd").supplies(game.terrain.backend.world_seed,identity)):
				cursor-=1;return false
		if not storage.protect(identity,true):cursor-=1;return false
		visited[identity]=true;game.terrain.changed_since_save=true
	return false

func rescan()->void:
	# A newly admitted region may contain an original chest. Per-chest markers
	# prevent repeats; the captured upper bound excludes later player placements.
	complete=false;started=false;pending=PackedInt64Array();cursor=0
