#include "experimental/region_snapshot.hpp"
#include <chrono>
#include <cstdio>
using namespace terraforest::experimental;
using Clock=std::chrono::steady_clock;
static double elapsed(Clock::time_point start){return std::chrono::duration<double,std::milli>(Clock::now()-start).count();}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;
 int failures=0;
 for(int site=0;site<3;site++)for(int size:{16,32})for(int repetition=0;repetition<3;repetition++){
  World w;w.init();int x=site==0?960:1280,z=x;
  if(site==2){V3 lo,hi;int changes;V3 p={1296,w.height(1296,1296),1296};w.edit(p,p,5,0,false,1,lo,hi,changes);}
  auto reference=build_world_region(w,x,z,size);
  RegionSnapshot snapshot;auto start=Clock::now();auto status=snapshot.capture(w,x,z,size);double capture_ms=elapsed(start);
  int revision=w.revision;
  // Destruction poisons any design accidentally retaining World-owned pages.
  w.release();
  start=Clock::now();auto result=snapshot.mesh();double mesh_ms=elapsed(start);
  bool ok=status==MeshStatus::ok&&reference.status==MeshStatus::ok&&result.status==MeshStatus::ok&&snapshot.revision()==revision&&!(reference.p!=result.p)&&!(reference.indices!=result.indices);
  failures+=!ok;
  printf("{\"site\":%d,\"size\":%d,\"repetition\":%d,\"capture_ms\":%.6f,\"mesh_ms\":%.6f,\"bytes\":%zu,\"passed\":%s}\n",site,size,repetition,capture_ms,mesh_ms,snapshot.bytes(),ok?"true":"false");
 }
 return failures?1:0;
}
