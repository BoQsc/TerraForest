#include "experimental/sparse_region_snapshot.hpp"
#include <cstdio>
#include <thread>
#include <atomic>
using namespace terraforest::experimental;
struct Allocation {
 int calls=0,fail=0,live=0;
 static void*alloc(void*p,size_t n){auto&s=*static_cast<Allocation*>(p);if(++s.calls==s.fail)return nullptr;void*v=std::malloc(n);if(v)s.live++;return v;}
 static void free(void*p,void*v){static_cast<Allocation*>(p)->live--;std::free(v);}
};
struct Cancellation {int calls=0,fail=0;static bool check(void*p){auto&s=*static_cast<Cancellation*>(p);return ++s.calls==s.fail;}};
int failures=0;
void check(bool ok,const char*name){printf("{\"name\":\"%s\",\"passed\":%s}\n",name,ok?"true":"false");failures+=!ok;}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;
 World w;w.init();V3 lo,hi;int changes;V3 p={1296,w.height(1296,1296),1296};w.edit(p,p,5,0,false,1,lo,hi,changes);
 auto reference=build_world_region(w,1280,1280,32);
 auto equal=[&](const Result&r){return r.status==MeshStatus::ok&&!(r.p!=reference.p)&&!(r.indices!=reference.indices);};
 SparseRegionSnapshot source;source.capture(w,1280,1280,32);int revision=source.revision();
 SparseRegionSnapshot moved(std::move(source));
 bool invalid_source=source.revision()==-1;
 // Check metadata first so the pre-fix ownership bug is reported without UB.
 check(invalid_source&&source.mesh().status==MeshStatus::invalid_input,"move constructor invalidates source");
 check(moved.revision()==revision&&equal(moved.mesh()),"moved destination preserves geometry");
 SparseRegionSnapshot assigned;assigned.capture(w,960,960,16);assigned=std::move(moved);
 check(moved.revision()==-1&&moved.mesh().status==MeshStatus::invalid_input&&equal(assigned.mesh()),"move assignment replaces ownership and invalidates source");
 bool allocations_ok=true;
 for(int fail=1;fail<=2;fail++){
  Allocation allocation;allocation.fail=fail;MeshLimits limits;limits.sampler_allocator={&allocation,Allocation::alloc,Allocation::free};
  SparseRegionSnapshot snapshot;
  allocations_ok&=snapshot.capture(w,1280,1280,32,limits)==MeshStatus::allocation_failed&&allocation.live==0&&snapshot.revision()==-1&&snapshot.mesh().status==MeshStatus::allocation_failed;
  allocations_ok&=snapshot.capture(w,1280,1280,32)==MeshStatus::ok&&equal(snapshot.mesh());
 }
 check(allocations_ok,"both capture allocations fail cleanly and recover");
 Cancellation count;MeshLimits limits;limits.context=&count;limits.cancel=Cancellation::check;
 SparseRegionSnapshot probe;probe.capture(w,1280,1280,32,limits);int checkpoints=count.calls;bool cancelled_ok=true;
 for(int fail=1;fail<=checkpoints;fail++){
  Cancellation cancellation;cancellation.fail=fail;limits.context=&cancellation;
  Allocation allocation;limits.sampler_allocator={&allocation,Allocation::alloc,Allocation::free};
  SparseRegionSnapshot snapshot;
  cancelled_ok&=snapshot.capture(w,1280,1280,32,limits)==MeshStatus::cancelled&&allocation.live==0&&snapshot.revision()==-1&&snapshot.mesh().status==MeshStatus::cancelled;
 }
 check(cancelled_ok&&checkpoints>153,"every capture cancellation checkpoint discards ownership");
 std::atomic<bool> entered{false},proceed{false};bool threaded_ok=false;
 std::thread worker([snapshot=std::move(assigned),&entered,&proceed,&threaded_ok,&equal]()mutable{
  entered.store(true);while(!proceed.load())std::this_thread::yield();threaded_ok=equal(snapshot.mesh());
 });
 while(!entered.load())std::this_thread::yield();
 w.edit(p,p,8,0,true,2,lo,hi,changes);w.release();proceed.store(true);worker.join();
 check(threaded_ok&&assigned.revision()==-1,"worker handoff survives source mutation and release");
 return failures?1:0;
}
