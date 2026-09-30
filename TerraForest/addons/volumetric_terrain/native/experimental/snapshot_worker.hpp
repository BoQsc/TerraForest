// SPDX-License-Identifier: 0BSD
#pragma once
#include "sparse_region_snapshot.hpp"
#include "snapshot_memory_budget.hpp"
#include "region_dependencies.hpp"
#include <condition_variable>
#include <mutex>
#include <thread>

namespace terraforest::experimental {
// Experimental geometry worker. Caller serializes submit against World mutation.
// Caller also serializes consume/publication against revision/epoch changes.
// consume's callback must not reenter this object or retain Result references.
class SnapshotWorker {
 enum State{empty,ready,running,complete};
 struct Slot{State state=empty;u64 serial=0,epoch=0,token=0;int revision=-1,validated_revision=-1,x=0,z=0,size=0;SparseRegionSnapshot snapshot;Result result;};
 SnapshotMemoryBudget snapshots_,meshes_;
 Slot slots_[2];
 std::mutex mutex_;
 std::condition_variable wake_;
 std::atomic<bool> stopping_{false};
 u64 serial_=0;
 std::thread thread_;
 void run(){
  for(;;){
   Slot*slot=nullptr;
   {
    std::unique_lock<std::mutex> lock(mutex_);
    wake_.wait(lock,[&]{return stopping_.load()||slots_[0].state==ready||slots_[1].state==ready;});
    for(auto&s:slots_)if(s.state==ready&&(!slot||s.serial<slot->serial))slot=&s;
    if(!slot)return;
    slot->state=running;
   }
   MeshLimits limits;limits.sampler_allocator=meshes_.allocator();limits.output_allocator=meshes_.allocator();limits.crossing_allocator=meshes_.allocator();
   limits.context=this;limits.cancel=[](void*p){return static_cast<SnapshotWorker*>(p)->stopping_.load();};
   Result result=slot->snapshot.mesh(limits);
   // No callable owner pointer escapes in the completed packet.
   result.limits.context=nullptr;result.limits.cancel=nullptr;
   {
    std::lock_guard<std::mutex> lock(mutex_);
    slot->snapshot=SparseRegionSnapshot{};slot->result=std::move(result);slot->state=complete;
   }
  }
 }
public:
 SnapshotWorker(size_t snapshot_bytes,size_t mesh_bytes):snapshots_(snapshot_bytes),meshes_(mesh_bytes),thread_([this]{run();}){}
 SnapshotWorker(const SnapshotWorker&)=delete;
 SnapshotWorker&operator=(const SnapshotWorker&)=delete;
 ~SnapshotWorker(){stop();}
 // Call stop from the owning thread, never a consume callback. Completed packets
 // remain consumable; destructor frees them before either budget is destroyed.
 void stop(){stopping_.store(true);wake_.notify_all();if(thread_.joinable())thread_.join();}
 bool submit(const World&w,int x,int z,int size,u64 epoch,u64 token){
  std::lock_guard<std::mutex> lock(mutex_);
  if(stopping_.load()||serial_==std::numeric_limits<u64>::max())return false;
  Slot*slot=nullptr;for(auto&s:slots_)if(s.state==empty){slot=&s;break;}
  if(!slot)return false;
  MeshLimits limits;limits.sampler_allocator=snapshots_.allocator();
  if(slot->snapshot.capture(w,x,z,size,limits)!=MeshStatus::ok)return false;
  slot->revision=slot->snapshot.revision();slot->validated_revision=slot->revision;slot->x=x;slot->z=z;slot->size=size;
  slot->epoch=epoch;slot->token=token;slot->serial=++serial_;slot->state=ready;wake_.notify_one();return true;
 }
 // Only a complete chain of certified, nonintersecting density edits advances
 // validity. An intersecting or unreported revision can never be resurrected.
 // Geometry sample bounds only: not sufficient for normals/materials/lighting.
 void observe_density_edit(int previous,int next,V3 lo,V3 hi){
  std::lock_guard<std::mutex> lock(mutex_);
  if(next<=previous)return;
  for(auto&s:slots_)if(s.state!=empty&&s.validated_revision==previous&&!edit_affects_region(s.x,s.z,s.size,lo,hi))s.validated_revision=next;
 }
 template<class Consumer>int consume(u64 epoch,int revision,Consumer&&consumer){
  std::lock_guard<std::mutex> lock(mutex_);int count=0;
  for(auto&s:slots_)if(s.state==complete){
   bool stale=s.epoch!=epoch||s.validated_revision!=revision;
   if(stale)s.result.discard(MeshStatus::cancelled);
   consumer(s.token,s.epoch,s.revision,stale,static_cast<const Result&>(s.result));
   s.result=Result{};s.state=empty;count++;
  }
  return count;
 }
 size_t snapshot_bytes()const{return snapshots_.used();}
 size_t mesh_bytes()const{return meshes_.used();}
};
}
