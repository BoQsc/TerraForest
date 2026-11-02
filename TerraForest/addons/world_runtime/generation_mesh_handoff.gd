# SPDX-License-Identifier: 0BSD
extends RefCounted
# One process-local, bounded handoff. Canonical loading/validation still runs;
# only derived mesh work for an identical verified checkpoint may be reused.
const LIMIT_BYTES:=192*1024*1024
const LIMIT_ROWS:=512
static var waiting:RefCounted
var rows:Dictionary={}
var bytes:=0
var epoch:=-1
var identity:=""
var compatibility:=""
var hits:=0
func remember(key:Vector3i,row:Dictionary,current_epoch:int)->void:
 if row.has("error") or row.get("cancelled",false):return
 if epoch!=current_epoch:rows.clear();bytes=0;epoch=current_epoch
 var size:=int(row.get("bytes",0))
 if size<0 or bytes-int(rows.get(key,{}).get("bytes",0))+size>LIMIT_BYTES or (not rows.has(key) and rows.size()>=LIMIT_ROWS):return
 bytes-=int(rows.get(key,{}).get("bytes",0))
 rows[key]=row.duplicate(true);bytes+=size
func seal(checkpoint:String,signature:String,current_epoch:int)->bool:
 if checkpoint.length()!=64 or signature.is_empty() or epoch!=current_epoch or rows.is_empty():return false
 identity=checkpoint;compatibility=signature;return true
func accepts(checkpoint:String,signature:String)->bool:
 return not identity.is_empty() and identity==checkpoint and compatibility==signature
func take(key:Vector3i)->Dictionary:
 if not rows.has(key):return {}
 var row:Dictionary=rows[key];rows.erase(key);bytes-=int(row.bytes);hits+=1
 row["worker_ms"]=0.0;row["region_stages"]={};row["handoff_cached"]=true
 return row
static func publish(cache:RefCounted)->void:waiting=cache
static func consume()->RefCounted:
 var cache:=waiting;waiting=null;return cache
