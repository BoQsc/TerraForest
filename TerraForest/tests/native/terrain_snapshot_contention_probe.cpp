// Compare identical candidate geometry with/without meshing under the world lock.
#include "experimental/sparse_region_snapshot.hpp"
#include "experimental/density_ray.hpp"
#include <atomic>
#include <chrono>
#include <cstdio>
#include <mutex>
#include <thread>
using namespace terraforest::experimental;
using Clock=std::chrono::steady_clock;
static double ms(Clock::time_point start){return std::chrono::duration<double,std::milli>(Clock::now()-start).count();}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;
 int failures=0;
 for(int fixture=0;fixture<3;fixture++)for(int mode=0;mode<2;mode++)for(int repetition=0;repetition<3;repetition++){
  World w;w.init();int x=fixture==0?960:1280;
  if(fixture==1){V3 lo,hi;int changes;V3 p={1296,w.height(1296,1296),1296};w.edit(p,p,5,0,false,1,lo,hi,changes);}
  if(fixture==2){x=1287;for(int py=0;py<=16;py++)for(int pz=x>>4;pz<=(x+32)>>4;pz++)for(int px=x>>4;px<=(x+32)>>4;px++){
   Page*p=w.ensure(px,py,pz);if(!p)return 2;
   for(int j=0;j<PAGE_SAMPLES;j++)p->d[j]=i16(((j+px*13+py*7+pz*17)%8193)-4096);
  }}
  auto expected=build_world_region(w,x,x,32);if(expected.status!=MeshStatus::ok)return 3;
  std::mutex world_mutex;std::atomic<bool> started{false},done{false};
  int completed=0,mesh_failures=0;size_t peak_snapshot=0;double hold_max=0;
  auto run_start=Clock::now();
  std::thread worker([&]{
   for(int job=0;job<12;job++){
    Result result;
    if(mode==0){
     std::lock_guard<std::mutex> lock(world_mutex);auto begin=Clock::now();started.store(true);
     result=build_world_region(w,x,x,32);hold_max=std::max(hold_max,ms(begin));
    }else{
     SparseRegionSnapshot snapshot;
     {
      std::lock_guard<std::mutex> lock(world_mutex);auto begin=Clock::now();started.store(true);
      if(snapshot.capture(w,x,x,32)!=MeshStatus::ok)mesh_failures++;
      hold_max=std::max(hold_max,ms(begin));
     }
     peak_snapshot=std::max(peak_snapshot,snapshot.bytes());
     result=snapshot.mesh();
    }
    if(result.status!=MeshStatus::ok||result.p!=expected.p||result.indices!=expected.indices)mesh_failures++;
    completed++;
    // Same explicit yield in both modes; do not monopolize the mutex by design.
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
   }
   done.store(true);
  });
  while(!started.load())std::this_thread::yield();
  int queries=0,query_failures=0;std::vector<double> latency;
  do{
   auto begin=Clock::now();DensityHit hit;
   {std::lock_guard<std::mutex> lock(world_mutex);hit=trace_world_density(w,{100,1.02f,100},{100,.98f,100});}
   latency.push_back(ms(begin));queries++;if(hit.status!=RayStatus::hit)query_failures++;
   std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }while(!done.load());
  worker.join();double elapsed=ms(run_start);w.release();
  bool ok=completed==12&&mesh_failures==0&&query_failures==0&&queries>0;failures+=!ok;
  printf("{\"fixture\":%d,\"sparse\":%s,\"repetition\":%d,\"meshes\":%d,\"queries\":%d,\"hold_max_ms\":%.6f,\"run_ms\":%.6f,\"peak_snapshot_bytes\":%zu,\"passed\":%s,\"latency_ms\":[",fixture,mode?"true":"false",repetition,completed,queries,hold_max,elapsed,peak_snapshot,ok?"true":"false");
  for(size_t i=0;i<latency.size();i++)printf("%s%.6f",i?",":"",latency[i]);
  printf("]}\n");
 }
 return failures?1:0;
}
