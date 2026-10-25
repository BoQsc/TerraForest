extends RefCounted
var mutex:=Mutex.new()
var state:Dictionary={}
func record(activity:String,completed:int=0,total:int=0,work:String="")->void:
 mutex.lock();state={"activity":activity,"completed":completed,"total":total,"work":work};mutex.unlock()
func snapshot()->Dictionary:
 mutex.lock();var result:=state.duplicate();mutex.unlock();return result
