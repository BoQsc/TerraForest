extends RefCounted
var mutex:=Mutex.new()
var state:Dictionary={}
var phases:Array=[]
var phase_started:=0
func record(activity:String,completed:int=0,total:int=0,work:String="")->void:
 mutex.lock()
 var now:=Time.get_ticks_usec()
 if state.get("activity","")!=activity:
  if phase_started>0 and phases.size()<128:phases.append({"activity":state.activity,"microseconds":now-phase_started})
  phase_started=now
 state={"activity":activity,"completed":completed,"total":total,"work":work};mutex.unlock()
func snapshot()->Dictionary:
 mutex.lock();var result:=state.duplicate();mutex.unlock();return result
func timings()->Array:
 mutex.lock();var result:=phases.duplicate()
 if phase_started>0:result.append({"activity":state.activity,"microseconds":Time.get_ticks_usec()-phase_started})
 mutex.unlock();return result
