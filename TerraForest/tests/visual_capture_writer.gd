# SPDX-License-Identifier: 0BSD
extends RefCounted
# Test-only PNG writer. Each job owns a detached viewport Image. Rendering and
# GPU readback stay on the main thread; compression/file I/O run on one worker.
# Admission includes the active job, bounding retained images to two frames.
var _thread:=Thread.new()
var _mutex:=Mutex.new()
var _wake:=Semaphore.new()
var _queue:Array=[]
var _active:=0
var _stopping:=false
var _records:Array=[]
func start()->Error:return _thread.start(_run)
func pending()->int:
 _mutex.lock();var count:int=_queue.size()+_active;_mutex.unlock();return count
func submit(image:Image,path:String)->bool:
 _mutex.lock()
 if _stopping or _queue.size()+_active>=2:_mutex.unlock();return false
 _queue.append({"image":image,"path":path});_mutex.unlock();_wake.post();return true
func _run():
 while true:
  _wake.wait();_mutex.lock()
  if _queue.is_empty():
   var stop:=_stopping;_mutex.unlock()
   if stop:return
   continue
  var job:Dictionary=_queue.pop_front();_active=1;_mutex.unlock()
  var start_us:=Time.get_ticks_usec()
  var status:int=job.image.save_png(job.path)
  var elapsed:float=(Time.get_ticks_usec()-start_us)/1000.0
  _mutex.lock();_records.append({"path":job.path,"png_ms":elapsed,"error":status});job.clear();_active=0;_mutex.unlock()
func close()->Array:
 _mutex.lock();_stopping=true;_mutex.unlock();_wake.post()
 if _thread.is_started():_thread.wait_to_finish()
 return _records.duplicate(true)
