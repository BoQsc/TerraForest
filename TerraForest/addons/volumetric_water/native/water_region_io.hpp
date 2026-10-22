// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_region_store.hpp"
#include <condition_variable>
#include <deque>
#include <thread>
namespace terraforest {
// Bounded region I/O. No live water/scene pointers cross to this worker.
class NativeWaterRegionIO : public godot::RefCounted {
 GDCLASS(NativeWaterRegionIO,godot::RefCounted)
 struct Job {int64_t ticket=0,epoch=0,bytes=0;bool write=false,checkpoint=false;godot::PackedInt32Array keys;godot::Vector3i coordinate;godot::PackedByteArray payload;};
 struct Done {godot::Dictionary value;int64_t bytes=0;};
 godot::Ref<NativeWaterRegionStore> store;
 std::mutex mutex;std::condition_variable wake;std::thread worker;
 std::deque<Job> pending;std::deque<Done> completed;
 bool running=false,stopping=false;int64_t epoch=0,next=1,reserved=0,limit=0,count=0,max_count=0,high_bytes=0;
 void run(){for(;;){Job job;{std::unique_lock<std::mutex> lock(mutex);wake.wait(lock,[&]{return stopping||!pending.empty();});if(stopping)return;job=std::move(pending.front());pending.pop_front();}
   godot::Dictionary reply;
   if(job.checkpoint){godot::Array digests;for(int64_t i=0;i<job.payload.size();i+=32)digests.append(job.payload.slice(i,i+32));reply=store->publish_checkpoint(job.keys,digests);}
   else reply=job.write?store->publish_region(job.coordinate,job.payload):store->read_region(job.payload,job.coordinate);
   reply["checkpoint_job"]=job.checkpoint;
   reply["ticket"]=job.ticket;reply["epoch"]=job.epoch;reply["coordinate"]=job.coordinate;reply["write"]=job.write;
   std::lock_guard<std::mutex> lock(mutex);
   if(stopping||job.epoch!=epoch){reserved-=job.bytes;--count;}else completed.push_back({reply,job.bytes});
  }}
 int64_t request(bool write,const godot::Vector3i &p,const godot::PackedByteArray &payload,int64_t wanted_epoch){
  std::lock_guard<std::mutex> lock(mutex);
  int64_t bytes=write?payload.size():8*1024*1024;
  if(!running||stopping||wanted_epoch!=epoch||p.x<0||p.x>=500||p.y<0||p.y>=64||p.z<0||p.z>=500||bytes<=0||bytes>8*1024*1024||(!write&&payload.size()!=32)||count>=max_count||bytes>limit-reserved)return 0;
  Job job;job.ticket=next++;job.epoch=epoch;job.coordinate=p;job.write=write;job.bytes=bytes;job.payload=payload;
  pending.push_back(std::move(job));reserved+=bytes;++count;high_bytes=std::max(high_bytes,reserved);wake.notify_one();return next-1;
 }
protected:
 static void _bind_methods(){
  godot::ClassDB::bind_method(godot::D_METHOD("configure","store","max_requests","max_bytes"),&NativeWaterRegionIO::configure);
  godot::ClassDB::bind_method(godot::D_METHOD("request_read","checkpoint","coordinate","epoch"),&NativeWaterRegionIO::request_read);
  godot::ClassDB::bind_method(godot::D_METHOD("request_write","coordinate","packet","epoch"),&NativeWaterRegionIO::request_write);
  godot::ClassDB::bind_method(godot::D_METHOD("request_checkpoint","coordinates","digests","epoch"),&NativeWaterRegionIO::request_checkpoint);
  godot::ClassDB::bind_method(godot::D_METHOD("poll"),&NativeWaterRegionIO::poll);
  godot::ClassDB::bind_method(godot::D_METHOD("cancel_epoch","epoch"),&NativeWaterRegionIO::cancel_epoch);
  godot::ClassDB::bind_method(godot::D_METHOD("stats"),&NativeWaterRegionIO::stats);
  godot::ClassDB::bind_method(godot::D_METHOD("close"),&NativeWaterRegionIO::close);
 }
public:
 ~NativeWaterRegionIO(){close();}
 bool configure(const godot::Ref<NativeWaterRegionStore> &value,int64_t requests,int64_t bytes){
  std::lock_guard<std::mutex> lock(mutex);if(running||value.is_null()||requests<1||requests>32||bytes<8*1024*1024||bytes>64*1024*1024)return false;
  store=value;max_count=requests;limit=bytes;stopping=false;running=true;worker=std::thread([this]{run();});return true;
 }
 int64_t request_read(const godot::PackedByteArray &checkpoint,const godot::Vector3i &p,int64_t epoch){return request(false,p,checkpoint,epoch);}
 int64_t request_write(const godot::Vector3i &p,const godot::PackedByteArray &packet,int64_t epoch){return request(true,p,packet,epoch);}
 int64_t request_checkpoint(const godot::PackedInt32Array &keys,const godot::PackedByteArray &digests,int64_t wanted_epoch){
  std::lock_guard<std::mutex> lock(mutex);
  if(!running||stopping||wanted_epoch!=epoch||keys.size()%3||keys.size()/3>65536||digests.size()!=keys.size()/3*32)return 0;
  // Includes packed submission and fixed working reservation for blob validation.
  int64_t bytes=keys.size()*4+digests.size()+8*1024*1024;
  if(count>=max_count||bytes>limit-reserved)return 0;
  Job job;job.ticket=next++;job.epoch=epoch;job.bytes=bytes;job.checkpoint=true;job.keys=keys;job.payload=digests;
  pending.push_back(std::move(job));reserved+=bytes;++count;high_bytes=std::max(high_bytes,reserved);wake.notify_one();return next-1;
 }
 godot::Dictionary poll(){std::lock_guard<std::mutex> lock(mutex);if(completed.empty())return {};auto done=std::move(completed.front());completed.pop_front();reserved-=done.bytes;--count;return done.value;}
 bool cancel_epoch(int64_t value){std::lock_guard<std::mutex> lock(mutex);if(value<=epoch)return false;epoch=value;
  for(const auto &job:pending){reserved-=job.bytes;--count;}pending.clear();
  for(const auto &done:completed){reserved-=done.bytes;--count;}completed.clear();return true;
 }
 godot::Dictionary stats(){std::lock_guard<std::mutex> lock(mutex);godot::Dictionary out;out["outstanding"]=count;out["reserved_bytes"]=reserved;out["high_bytes"]=high_bytes;out["epoch"]=epoch;return out;}
 void close(){ {std::lock_guard<std::mutex> lock(mutex);if(!running)return;stopping=true;wake.notify_one();}
  if(worker.joinable())worker.join();std::lock_guard<std::mutex> lock(mutex);pending.clear();completed.clear();reserved=0;count=0;running=false;store.unref();
 }
};
}
