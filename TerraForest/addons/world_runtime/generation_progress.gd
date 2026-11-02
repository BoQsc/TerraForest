# SPDX-License-Identifier: 0BSD
extends RefCounted
# Real stage observations and work counts; presentation derives a stage-weighted estimate.
static var observations:Dictionary={}
static func write(path:String,stage:String,completed:int=0,total:int=0,details:Dictionary={})->bool:
 if path.is_empty() or completed<0 or total<0 or (total>0 and completed>total):return false
 var now:=Time.get_ticks_usec()
 # Activity text includes counters/resource names. Timing it as separate stages
 # exhausted the record budget before baking began. Aggregate stable stage names.
 if not observations.has(path):observations[path]={"started":now,"stage":stage,"since":now,"timings":[],"dropped_us":0,"dropped_transitions":0}
 var profile:Dictionary=observations[path]
 if profile.stage!=stage:
  var elapsed:=now-int(profile.since)
  var recorded:=false
  for timing:Dictionary in profile.timings:
   if timing.stage==profile.stage:
    timing.microseconds+=elapsed;timing.visits+=1;recorded=true;break
  if not recorded:
   if profile.timings.size()<64:profile.timings.append({"stage":profile.stage,"microseconds":elapsed,"visits":1})
   else:profile.dropped_us+=elapsed;profile.dropped_transitions+=1
  profile.stage=stage;profile.since=now
 var file:=FileAccess.open(path+".pending",FileAccess.WRITE)
 if file==null:return false
 file.store_string(JSON.stringify({"timing_schema":2,"stage":stage,"completed":completed,"total":total,"details":details,"elapsed_microseconds":now-int(profile.started),"stage_microseconds":now-int(profile.since),"timings":profile.timings,"timings_dropped_microseconds":profile.dropped_us,"timings_dropped_transitions":profile.dropped_transitions}));file.close()
 return DirAccess.rename_absolute(path+".pending",path)==OK
static func read(path:String)->Dictionary:
 var file:=FileAccess.open(path,FileAccess.READ) if FileAccess.file_exists(path) else null
 if file==null or file.get_length()>16384:return {}
 var data=JSON.parse_string(file.get_as_text())
 if not data is Dictionary or not data.get("stage",null) is String:return {}
 var completed:=int(data.get("completed",-1));var total:=int(data.get("total",-1))
 if completed<0 or total<0 or completed>total or str(data.stage).length()>96:return {}
 return data
