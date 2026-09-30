#include "experimental/sparse_region_snapshot.hpp"
#include <chrono>
#include <cstdio>
using namespace terraforest::experimental;
using Clock=std::chrono::steady_clock;
struct Failing {int calls=0,fail=0;static void*allocate(void*p,size_t n){auto&f=*static_cast<Failing*>(p);return ++f.calls==f.fail?nullptr:std::malloc(n);}};
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;int failures=0;
 for(int site=0;site<5;site++)for(int size:{16,32}){
  World w;w.init();int x=site==0?960:1280,z=x;
  if(site==2)x=z=1295;
  if(site==3)x=z=0;
  if(site==4)x=z=WORLD-size;
  if(site==1){V3 lo,hi;int changes;V3 p={1296,w.height(1296,1296),1296};w.edit(p,p,5,0,false,1,lo,hi,changes);}
  auto reference=build_world_region(w,x,z,size);
  auto original_normals=build_region_normals_cached(w,reference,x,z,size,MeshLimits{},true);
  if(site==2){
   int px=(x+size+1)>>4;
   for(int py=0;py<=16;py++)for(int pz=z>>4;pz<=(z+size+1)>>4;pz++){
    Page*p=w.ensure(px,py,pz);if(!p)return 2;
    for(int j=0;j<PAGE_SAMPLES;j++)p->d[j]=i16(imx(-4096,int(p->d[j])-512));
   }
  }
  auto after_geometry=build_world_region(w,x,z,size);
  auto expected=build_region_normals_cached(w,after_geometry,x,z,size,MeshLimits{},true);
  SparseRegionSnapshot snapshot;auto status=snapshot.capture(w,x,z,size,MeshLimits{},true);w.release();
  auto mesh=snapshot.mesh();auto start=Clock::now();auto normals=snapshot.normals(mesh);
  double elapsed=std::chrono::duration<double,std::milli>(Clock::now()-start).count();
  bool ok=status==MeshStatus::ok&&expected.status==MeshStatus::ok&&normals.status==MeshStatus::ok&&!(mesh.p!=after_geometry.p)&&!(mesh.indices!=after_geometry.indices)&&!(normals.values!=expected.values);
  for(int failure=1;failure<=3;failure++){
   Failing injected;injected.fail=failure==3?1:failure;MeshLimits limits;
   BufferAllocator allocator;allocator.context=&injected;allocator.allocate=Failing::allocate;
   if(failure==3)limits.output_allocator=allocator;else limits.sampler_allocator=allocator;
   auto failed=snapshot.normals(mesh,limits);ok&=failed.status==MeshStatus::allocation_failed&&failed.values.empty();
  }
  MeshLimits cancelled;cancelled.cancel=[](void*){return true;};
  auto stopped=snapshot.normals(mesh,cancelled);ok&=stopped.status==MeshStatus::cancelled&&stopped.values.empty();
  bool halo=site!=2||(!(reference.p!=after_geometry.p)&&!(reference.indices!=after_geometry.indices)&&original_normals.values!=expected.values);
  failures+=!ok||!halo;
  printf("{\"site\":%d,\"size\":%d,\"passed\":%s,\"halo_control\":%s,\"normal_ms\":%.6f,\"snapshot_bytes\":%zu,\"normal_scratch\":%zu}\n",site,size,ok?"true":"false",halo?"true":"false",elapsed,snapshot.bytes(),normals.scratch_bytes);
 }
 return failures?1:0;
}
