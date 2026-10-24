# SPDX-License-Identifier: 0BSD
extends RefCounted
# Local durations use the monotonic clock. Unix time is used once when crossing
# process boundaries so generation, verification and first load share an origin.
const ARGUMENT:="--loading-started-ms="
const WINDOW_US:=30000000
const STALE_US:=10000000
var started_us:=0
var carried_us:=0
var ended_us:=-1
var last_change_us:=0
var progress:=0.0
var changes:=0
var status:="working"
var samples:Array[Vector2]=[]

static func unix_milliseconds()->int:
 return int(Time.get_unix_time_from_system()*1000.0)

static func requested_start()->int:
 for arg:String in PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args())):
  if arg.begins_with(ARGUMENT):
   var value:=arg.trim_prefix(ARGUMENT)
   if value.is_valid_int():return maxi(0,int(value))
 return 0

static func carried_elapsed(start_ms:int)->int:
 return maxi(0,unix_milliseconds()-start_ms)*1000 if start_ms>0 else 0

func reset(now_us:int,baseline:float=0,elapsed_us:int=0)->void:
 started_us=now_us;carried_us=maxi(0,elapsed_us);ended_us=-1
 progress=clampf(baseline,0,100);last_change_us=now_us;changes=0;status="working"
 samples.assign([Vector2(now_us,progress)])

func observe(value:float,now_us:int)->void:
 if status!="working":return
 var next:=clampf(value,progress,100)
 if next>progress+0.001:last_change_us=now_us;changes+=1
 progress=next
 if now_us-int(samples.back().x)>=1000000:samples.append(Vector2(now_us,progress))
 while samples.size()>2 and int(samples[1].x)<now_us-WINDOW_US:samples.pop_front()
 if progress>=100:stop("complete",now_us)

func stop(reason:String,now_us:int)->void:
 status=reason
 if reason!="cancelling" and ended_us<0:ended_us=now_us

func snapshot(now_us:int)->Dictionary:
 var elapsed:=carried_us+maxi(0,(ended_us if ended_us>=0 else now_us)-started_us)
 var remaining:Variant=null
 var estimate_state:="estimating"
 if status=="complete":remaining=0;estimate_state="complete"
 elif status!="working":estimate_state=status
 elif now_us-last_change_us>=STALE_US:estimate_state="recalculating"
 elif changes>=2 and now_us-started_us>=2000000:
  var span:=now_us-int(samples.front().x)
  var advance:float=progress-samples.front().y
  if span>=2000000 and advance>=1.0:
   remaining=maxi(1,int(ceil((100.0-progress)*float(span)/advance)))
   estimate_state="approximate"
 return {"elapsed_us":elapsed,"remaining_us":remaining,"estimate_state":estimate_state,"status":status,"progress":progress,"window_us":WINDOW_US,"sample_count":samples.size()}

static func duration(microseconds:int,round_up:bool=false)->String:
 var seconds:int=int(ceil(maxi(0,microseconds)/1000000.0)) if round_up else maxi(0,microseconds)/1000000
 if seconds>=3600:return "%d:%02d:%02d"%[seconds/3600,(seconds/60)%60,seconds%60]
 return "%02d:%02d"%[seconds/60,seconds%60]

static func label(state:Dictionary)->String:
 var elapsed:=duration(int(state.elapsed_us))
 match str(state.estimate_state):
  "complete":return "Total %s · Complete"%elapsed
  "approximate":return "Elapsed %s · Est. remaining ~%s"%[elapsed,duration(int(state.remaining_us),true)]
  "estimating":return "Elapsed %s · Est. remaining: estimating…"%elapsed
  "recalculating":return "Elapsed %s · Est. remaining: recalculating…"%elapsed
  "cancelling":return "Elapsed %s · Cancelling…"%elapsed
  "failed":return "Elapsed %s · Failed"%elapsed
  "cancelled":return "Elapsed %s · Cancelled"%elapsed
 return "Elapsed %s"%elapsed
