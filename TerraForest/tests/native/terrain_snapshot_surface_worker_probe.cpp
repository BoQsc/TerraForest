#include "experimental/snapshot_worker.hpp"
#include <chrono>
#include <cstdio>
using namespace terraforest::experimental;
int failures=0;
void check(bool ok,const char*name){printf("{\"name\":\"%s\",\"passed\":%s}\n",name,ok?"true":"false");failures+=!ok;}
template<class F>int drain(SnapshotWorker&w,int revision,F&&fn){
 int count=0;auto end=std::chrono::steady_clock::now()+std::chrono::seconds(5);
 while(count<2&&std::chrono::steady_clock::now()<end){count+=w.consume_surface(0,revision,fn);if(count<2)std::this_thread::sleep_for(std::chrono::milliseconds(1));}return count;
}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;
 World world;world.init();auto geometry=build_world_region(world,1295,1295,32);
 auto normals=build_region_normals_cached(world,geometry,1295,1295,32,MeshLimits{},true);
 SnapshotWorker worker(3*1024*1024,32*1024*1024);
 bool admitted=worker.submit(world,1295,1295,32,0,1)&&worker.submit(world,1295,1295,32,0,2);
 world.release();bool same=true;
 int count=drain(worker,0,[&](u64,u64,int,bool stale,const Result&r,const NormalResult&n){same&=!stale&&r.status==MeshStatus::ok&&n.status==MeshStatus::ok&&!(geometry.p!=r.p)&&!(geometry.indices!=r.indices)&&!(normals.values!=n.values);});
 check(admitted&&count==2&&same,"worker preserves exact geometry and normals after source release");
 check(worker.snapshot_bytes()==0&&worker.mesh_bytes()==0,"surface consumption releases geometry and normal allocations");
 world.init();admitted=worker.submit(world,1295,1295,32,0,3)&&worker.submit(world,1295,1295,32,0,4);
 // Alter the next page beyond the region's last geometry sample x=1327.
 for(int y=0;y<=16;y++)for(int z=80;z<=83;z++){
  Page*p=world.ensure(83,y,z);if(!p)return 2;
  for(int j=0;j<PAGE_SAMPLES;j++)p->d[j]=i16(imx(-4096,int(p->d[j])-512));
 }
 world.revision=1;worker.observe_density_edit(0,1,{1328,0,1280},{1343,256,1343});
 auto after=build_world_region(world,1295,1295,32);auto after_normals=build_region_normals_cached(world,after,1295,1295,32,MeshLimits{},true);
 check(!(geometry.p!=after.p)&&!(geometry.indices!=after.indices)&&normals.values!=after_normals.values,"positive border edit changes normals without geometry");
 bool rejected=true;count=drain(worker,1,[&](u64,u64,int,bool stale,const Result&r,const NormalResult&n){rejected&=stale&&r.status==MeshStatus::cancelled&&n.status==MeshStatus::cancelled&&r.p.empty()&&r.indices.empty()&&n.values.empty();});
 check(admitted&&count==2&&rejected,"normal border invalidation discards the entire surface");
 worker.stop();world.release();return failures?1:0;
}
