# SPDX-License-Identifier: 0BSD
extends RefCounted
# Stage-weighted completion estimate, never a timer. Final 6% belongs to playback.
const GENERATION_STAGES={
 "Planning terrain, streets and building sites":Vector2(0,5),
 "Baking roads and foundations before terrain loading":Vector2(5,8),
 "Initializing generated terrain data":Vector2(5,8),
 "Building roads and foundations":Vector2(8,30),
 "Grading roads and foundations":Vector2(8,30),
 "Preparing water sources":Vector2(30,36),
 "Preparing generated world data":Vector2(30,36),
 "Loading water sources":Vector2(36,38),
 "Baking terrain overview":Vector2(38,42),
 "Placing buildings and interiors":Vector2(42,62),
 "Baking streets and location metadata":Vector2(62,65),
 "Baking destructible sidewalk plates":Vector2(62,65),
 "Photographing the generated world":Vector2(65,78),
 "Capturing world photographs":Vector2(65,78),
 "Saving generated world":Vector2(78,82),
 "Caching the saved world map":Vector2(82,88),
 "Baking saved world map layers":Vector2(82,88),
 "World generation complete":Vector2(88,88),
 "Verifying saved terrain, buildings and water":Vector2(88,92)
}
static func generation(stage:String,completed:int=0,total:int=0,details:Dictionary={})->float:
 var span:Vector2=GENERATION_STAGES.get(stage,Vector2.ZERO)
 return lerpf(span.x,span.y,clampf(float(details.get("stage_fraction",float(completed)/total if total>0 else 0.0)),0,1))
static func coordinator(state:String,detail:Dictionary)->float:
 match state:
  "verifying","recovering":return 88.0
  "publishing":return 92.0
  "ready":return 94.0
 return generation(str(detail.get("stage","")),int(detail.get("completed",0)),int(detail.get("total",0)),detail.get("details",{}))
static func loading(state:Dictionary,world_ready:bool,waiting_spawn:bool)->Dictionary:
 if not world_ready:return {"percent":0.0,"stage":"Reading saved world data"}
 if waiting_spawn:return {"percent":15.0,"stage":"Finding a safe player position"}
 var roots:float=clampf(float(state.get("coverage_ready",state.get("roots",0)))/maxi(1,int(state.get("coverage_total",state.get("root_total",0)))),0,1)
 var local:float=clampf(float(state.get("local",0))/maxi(1,int(state.get("local_total",0))),0,1)
 if state.get("ready",false):return {"percent":75.0,"stage":"Checking nearby objects"}
 return {"percent":20.0+20.0*roots+35.0*local,"stage":"Loading nearby terrain and collision" if local<1.0 else "Loading landscape coverage"}

static func loading_caption(stage:String,state:Dictionary)->String:
 if stage=="Loading landscape coverage":return "%s · %d / %d required areas ready"%[stage,state.get("coverage_ready",state.roots),state.get("coverage_total",state.root_total)]
 if stage=="Loading nearby terrain and collision":return "%s · %d / %d probes ready"%[stage,state.local,state.local_total]
 return stage

static func loading_work(state:Dictionary,terrain:Node)->String:
 var cache:Dictionary=terrain.derived_metrics
 return "Coverage %d/%d (%s) · collision %d/%d · worker: %s · queued %d · in flight %d · upload queue %d · cache hits %d / misses %d"%[state.get("coverage_ready",state.roots),state.get("coverage_total",state.root_total),state.get("coverage_scope","world"),state.local,state.local_total,state.worker,state.queued,terrain.in_flight.size(),terrain.staging.size(),int(cache.get("hits",0)),int(cache.get("misses",0))]
