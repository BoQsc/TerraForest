#include "experimental/sparse_region_snapshot.hpp"
#include <chrono>
#include <cstdio>
using namespace terraforest::experimental;
using Clock=std::chrono::steady_clock;
static double elapsed(Clock::time_point start){return std::chrono::duration<double,std::milli>(Clock::now()-start).count();}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;
 int failures=0;
 for(int site=0;site<6;site++)for(int size:{16,32})for(int repetition:{0,32,256}){
  World w;w.init();int x=site==0?960:1280,z=x;
  if(site==3)x=z=0;
  if(site==4)x=z=WORLD-size;
  if(site==5){
   x=z=1287;
   for(int py=0;py<=WORLD_Y/PAGE;py++)for(int pz=z>>4;pz<=(z+size)>>4;pz++)for(int px=x>>4;px<=(x+size)>>4;px++){
    Page*p=w.ensure(px,py,pz);if(!p)return 2;
    // Distinct values throughout every copied page expose slot/boundary errors.
    for(int j=0;j<PAGE_SAMPLES;j++)p->d[j]=i16(((j+px*13+py*7+pz*17)%8193)-4096);
   }
  }
  if(site==2){V3 lo,hi;int changes;V3 p={1296,w.height(1296,1296),1296};w.edit(p,p,5,0,false,1,lo,hi,changes);}
  for(int i=0;i<repetition;i++)w.ensure(32+i%16,4,32+i/16);
  auto reference=build_world_region(w,x,z,size);
  SparseRegionSnapshot snapshot;auto start=Clock::now();auto status=snapshot.capture(w,x,z,size);double capture_ms=elapsed(start);
  int revision=w.revision;
  // Destruction poisons any design accidentally retaining World-owned pages.
  w.release();
  start=Clock::now();auto result=snapshot.mesh();double mesh_ms=elapsed(start);
  bool ok=status==MeshStatus::ok&&reference.status==MeshStatus::ok&&result.status==MeshStatus::ok&&snapshot.revision()==revision&&snapshot.lookups()==(((x+size)>>4)-(x>>4)+1)*(((z+size)>>4)-(z>>4)+1)*17&&!(reference.p!=result.p)&&!(reference.indices!=result.indices);
  failures+=!ok;
  printf("{\"site\":%d,\"size\":%d,\"remote_pages\":%d,\"capture_ms\":%.6f,\"mesh_ms\":%.6f,\"bytes\":%zu,\"passed\":%s}\n",site,size,repetition,capture_ms,mesh_ms,snapshot.bytes(),ok?"true":"false");
 }
 return failures?1:0;
}
