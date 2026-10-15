# SPDX-License-Identifier: 0BSD
extends SceneTree
const Backend=preload("res://addons/volumetric_terrain/terrain_backend.gd")
class Core extends RefCounted:
 var revision:=7
 var epoch:=9
 func execute(command:PackedByteArray)->PackedByteArray:
  var reply:=PackedByteArray();reply.resize(16);reply.encode_u32(0,0x32505254)
  reply.encode_u32(12,epoch if command.decode_u32(0)==13 else revision)
  return reply
class Builder extends RefCounted:
 var calls:=0
 var required_calls:=3
 func sample_terrain(_core:Object,_budget:int,_revision:int,_epoch:int)->int:
  calls+=1
  return 1 if calls>=required_calls else 0
var failures:=0
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func request(builder:RefCounted)->Dictionary:
 return {"kind":"lake_slice","builder":builder,"token":42,"epoch":3,"revision":7,"density_revision":7,"build_epoch":9,"submitted_us":Time.get_ticks_usec()}
func _initialize():call_deferred("run")
func run():
 var backend:=Backend.new();var core:=Core.new();backend.native=core
 var builder:=Builder.new();backend._lake_pending=1
 backend.jobs.append({"kind":"save"})
 backend._execute_lake_slice(request(builder))
 check(backend.results.is_empty() and backend._lake_pending==1 and backend.jobs.size()==2,"Continuation keeps one reservation without interim result")
 backend._service_lake_slice()
 check(builder.calls==1 and backend.jobs[0].kind=="save","Continuation cannot cross queued save barrier")
 backend.jobs.pop_front()
 backend._service_lake_slice();backend._service_lake_slice()
 check(builder.calls==3 and backend.jobs.is_empty() and backend.results.size()==1,"Slices finish without a main-thread poll between them")
 var result:Array=backend.poll()
 check(result.size()==1 and result[0].status==1 and backend._lake_pending==0,"Terminal result releases reservation exactly once")
 builder=Builder.new();backend._lake_pending=1
 backend._execute_lake_slice(request(builder));core.epoch+=1
 backend._service_lake_slice();result=backend.poll()
 check(result.size()==1 and result[0].status==-4 and builder.calls==1 and backend._lake_pending==0,"Changed cancel epoch rejects continuation before sampling")
 core.epoch=9;builder=Builder.new();builder.required_calls=7;backend._lake_pending=1
 backend.jobs.append(request(builder))
 backend._service_lake_slice(100000)
 check(builder.calls==4 and backend.jobs.size()==1 and backend.results.is_empty(),"Service quantum stops after four slices even with time remaining")
 backend.jobs.push_front({"kind":"save"});backend._service_lake_slice(100000)
 check(builder.calls==4,"Multi-slice quantum still cannot cross save barrier")
 backend.jobs.pop_front();backend._service_lake_slice(100000);result=backend.poll()
 check(result.size()==1 and result[0].status==1 and backend._lake_pending==0,"Next quantum completes remaining slices")
 core.epoch=9;builder=Builder.new();backend._lake_pending=1;backend.stopping=true
 backend._execute_lake_slice(request(builder));result=backend.poll()
 check(result.size()==1 and result[0].status==0 and backend.jobs.is_empty() and backend._lake_pending==0,"Shutdown returns unfinished reservation without requeue")
 print("WATER_WORKER_CONTINUATION failures=",failures);quit(failures)
