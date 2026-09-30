#include "experimental/snapshot_memory_budget.hpp"
#include "experimental/sparse_region_snapshot.hpp"
#include <thread>
#include <cstdio>
using namespace terraforest::experimental;
int failures=0;
void check(bool ok,const char*name){printf("{\"name\":\"%s\",\"passed\":%s}\n",name,ok?"true":"false");failures+=!ok;}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;
 SnapshotMemoryBudget empty(0);auto a=empty.allocator();
 check(!a.allocate(a.context,1)&&empty.used()==0,"zero budget rejects allocation");
 check(!a.allocate(a.context,SIZE_MAX)&&empty.used()==0,"size overflow rejected before reservation");
 BufferAllocator fail;fail.allocate=[](void*,size_t)->void*{return nullptr;};
 SnapshotMemoryBudget rollback(4096,fail);a=rollback.allocator();
 check(!a.allocate(a.context,100)&&rollback.used()==0,"upstream allocation failure rolls back reservation");
 SnapshotMemoryBudget concurrent(2100);a=concurrent.allocator();
 std::atomic<int> ready{0},success{0};std::atomic<bool> go{false},release{false};
 std::thread threads[8];
 for(auto&t:threads)t=std::thread([&]{while(!go.load())std::this_thread::yield();void*p=a.allocate(a.context,1024);if(p)success++;ready++;while(!release.load())std::this_thread::yield();if(p)a.release(a.context,p);});
 go.store(true);while(ready.load()!=8)std::this_thread::yield();
 bool bounded=success==2&&concurrent.used()<=concurrent.limit()&&concurrent.peak()<=concurrent.limit();release.store(true);for(auto&t:threads)t.join();
 check(bounded&&concurrent.used()==0&&concurrent.denied()==6,"eight competing allocations respect shared capacity and release");
 World w;w.init();V3 lo,hi;int changes;V3 p={1296,w.height(1296,1296),1296};w.edit(p,p,5,0,false,1,lo,hi,changes);
 size_t required=0;
 {SnapshotMemoryBudget measured(2*1024*1024);MeshLimits limits;limits.sampler_allocator=measured.allocator();SparseRegionSnapshot snapshot;if(snapshot.capture(w,1280,1280,32,limits)!=MeshStatus::ok)return 2;required=measured.used();}
 SnapshotMemoryBudget budget(required);MeshLimits limits;limits.sampler_allocator=budget.allocator();
 bool admission_ok=false;
 {
  SparseRegionSnapshot first,second;
  bool accepted=first.capture(w,1280,1280,32,limits)==MeshStatus::ok;
  bool rejected=second.capture(w,1280,1280,32,limits)==MeshStatus::allocation_failed&&second.revision()==-1;
  admission_ok=accepted&&rejected&&budget.used()==required&&budget.peak()<=budget.limit();
  second=std::move(first);
  admission_ok&=first.revision()==-1&&budget.used()==required&&second.mesh().status==MeshStatus::ok;
 }
 check(admission_ok&&budget.used()==0,"snapshot admission rejection and moved ownership preserve exact accounting");
 {
  SparseRegionSnapshot recovered;
  check(recovered.capture(w,1280,1280,32,limits)==MeshStatus::ok&&budget.used()==required,"released capacity admits retry");
 }
 check(budget.used()==0,"final destruction returns all snapshot heap reservations");
 {
  MeshLimits cancelled=limits;cancelled.context=&budget;
  cancelled.cancel=[](void*p){return static_cast<SnapshotMemoryBudget*>(p)->used()>0;};
  SparseRegionSnapshot snapshot;
  check(snapshot.capture(w,1280,1280,32,cancelled)==MeshStatus::cancelled&&budget.used()==0&&snapshot.revision()==-1,"cancellation after allocation returns both reservations");
 }
 {
  SnapshotMemoryBudget growth(1000);FallibleBuffer<int> values;values.set_allocator(growth.allocator());
  bool initial=values.resize(100);size_t charged=growth.used();
  check(initial&&!values.resize(200)&&values.size()==100&&growth.used()==charged&&growth.peak()<=1000,"buffer growth accounts for old and replacement allocations together");
 }
 w.release();return failures?1:0;
}
