#include "experimental/region_surface.hpp"
#include "experimental/region_dependencies.hpp"
#include "experimental/snapshot_worker.hpp"
#include <array>
#include <map>
#include <vector>
#include <chrono>
#include <cstdio>
#include <cstring>
using namespace terraforest::experimental;
using Triangle=std::array<u32,18>;
using Triangles=std::map<Triangle,int>;
static double now(){return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();}
static void append(Triangles&out,const RegionSurface&s){
 for(size_t i=0;i<s.geometry.indices.size();i+=3){
  Triangle t{};
  for(int k=0;k<3;k++){u32 v=s.geometry.indices[i+k];std::memcpy(t.data()+k*6,&s.geometry.p[v],12);std::memcpy(t.data()+k*6+3,&s.normals.values[v],12);}
  Triangle canonical=t;for(int rotate=1;rotate<3;rotate++){Triangle r;for(int k=0;k<18;k++)r[k]=t[(k+rotate*6)%18];canonical=std::min(canonical,r);}out[canonical]++;
 }
}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;
 // Invalid ranges must fail before calling the layer provider.
 for(auto range:std::array<std::array<int,2>,5>{{{-1,32},{0,0},{32,31},{256,257},{0,257}}}){
  int calls=0;auto r=mesh_layers(960,960,32,true,[&](int)->const float*{calls++;return nullptr;},MeshLimits{},range[0],range[1]);
  if(r.status!=MeshStatus::invalid_input||calls||!r.p.empty()||!r.indices.empty())return 2;
 }
 V3 halo{970,65,970};
 if(edit_affects_region(960,960,32,halo,halo,32,64)||!edit_affects_region_normals(960,960,32,halo,halo,32,64))return 14;
 halo.y=64;if(!edit_affects_region(960,960,32,halo,halo,32,64))return 15;
 halo.y=31;if(edit_affects_region_normals(960,960,32,halo,halo,32,64))return 16;
 for(int origin:{960,1056,1280}){
  World w;w.init();auto whole=build_world_surface(w,origin,origin,32);if(!whole.ready())return 3;
  Triangles reference;append(reference,whole);
  // Includes an odd start and non-page-aligned cuts, not just aligned bricks.
  for(int partition=0;partition<2;partition++){
   std::vector<int> cuts=partition==0?std::vector<int>{0,32,64,96,128,160,192,224,256}:std::vector<int>{0,1,17,53,99,127,255,256};
   Triangles combined;size_t tris=0;double elapsed=0;
   for(size_t i=1;i<cuts.size();i++){
    double begin=now();auto brick=build_world_surface(w,origin,origin,32,MeshLimits{},cuts[i-1],cuts[i]);elapsed+=now()-begin;
    if(!brick.ready()||brick.y_begin!=cuts[i-1]||brick.y_end!=cuts[i])return 4;
    SparseRegionSnapshot snapshot;
    if(snapshot.capture(w,origin,origin,32,MeshLimits{},true,cuts[i-1],cuts[i])!=MeshStatus::ok)return 17;
    auto geometry=snapshot.mesh();auto normals=snapshot.normals(geometry);
    if(geometry.status!=MeshStatus::ok||normals.status!=MeshStatus::ok||geometry.p!=brick.geometry.p||geometry.indices!=brick.geometry.indices||normals.values!=brick.normals.values)return 18;
    for(V3 p:brick.geometry.p)if(p.y<cuts[i-1]||p.y>cuts[i])return 5;
    append(combined,brick);tris+=brick.geometry.indices.size()/3;
   }
   bool exact=combined==reference;if(!exact)return 6;
   printf("{\"kind\":\"partition\",\"origin\":%d,\"partition\":%d,\"triangles\":%zu,\"surface_ms\":%.6f,\"exact_oriented_geometry_and_normals\":true}\n",origin,partition,tris,elapsed);
  }
  std::vector<RegionSurface> bricks;
  for(int z=0;z<2;z++)for(int x=0;x<2;x++)for(int y=0;y<256;y+=32){auto s=build_world_surface(w,origin+x*32,origin+z*32,32,MeshLimits{},y,y+32);if(!s.ready())return 7;bricks.push_back(std::move(s));}
  // Face, edge, corner crossings in three dimensions, including a Y join.
  int base_y=std::max(32,int(w.height(float(origin+32),float(origin+32))-48)/32*32);
  for(int placement=0;placement<4;placement++){
   V3 p={float(origin+(placement>=2?32:16)),float(base_y+(placement>=1?32:16)),float(origin+(placement==3?32:16))};
   V3 lo,hi;int changes=0;if(!w.edit(p,p,2.5f,0,false,1,lo,hi,changes)||!changes)return 8;
   int affected=0;size_t triangles=0,vertex_bytes=0;double rebuild_ms=0;
   for(auto&s:bricks)if(edit_affects_region_normals(s.x,s.z,32,lo,hi,s.y_begin,s.y_end)){
    affected++;double begin=now();auto next=build_world_surface(w,s.x,s.z,32,MeshLimits{},s.y_begin,s.y_end);rebuild_ms+=now()-begin;
    if(!next.ready())return 9;triangles+=next.geometry.indices.size()/3;vertex_bytes+=next.geometry.p.size()*56+next.geometry.indices.size()*4;s=std::move(next);
   }
   if(affected!=(1<<placement))return 10;
   // A full-height rebuild per column proves both invalidation and horizontal
   // join parity after edits; no reference uses the new vertical range options.
   Triangles fresh,retained;double column_ms=0;size_t full_triangles=0;
   for(int z=0;z<2;z++)for(int x=0;x<2;x++){
    double begin=now();auto s=build_world_surface(w,origin+x*32,origin+z*32,32);column_ms+=now()-begin;
    if(!s.ready())return 11;full_triangles+=s.geometry.indices.size()/3;append(fresh,s);
   }
   for(const auto&s:bricks)append(retained,s);
   if(fresh!=retained)return 12;
   // Run actual bounded snapshots through the asynchronous worker after edits.
   SnapshotWorker worker(3*1024*1024,32*1024*1024);
   const auto& expected=bricks[size_t((p.y/32))];
   if(!worker.submit(w,expected.x,expected.z,32,1,1,nullptr,expected.y_begin,expected.y_end))return 19;
   bool received=false,parity=false;auto deadline=now()+5000;
   while(!received&&now()<deadline){
    worker.consume_surface(1,w.revision,[&](u64,u64,int,bool stale,const Result&r,const NormalResult&n){received=true;parity=!stale&&r.status==MeshStatus::ok&&n.status==MeshStatus::ok&&!(r.p!=expected.geometry.p)&&!(r.indices!=expected.geometry.indices)&&!(n.values!=expected.normals.values);});
    if(!received)std::this_thread::sleep_for(std::chrono::milliseconds(1));
   }
   worker.stop();if(!received||!parity||worker.snapshot_bytes()||worker.mesh_bytes())return 20;
   printf("{\"kind\":\"edit\",\"origin\":%d,\"placement\":%d,\"affected_bricks\":%d,\"triangles\":%zu,\"render_payload_bytes\":%zu,\"rebuild_ms\":%.6f,\"four_column_ms\":%.6f,\"four_column_triangles\":%zu,\"exact_oriented_geometry_and_normals\":true}\n",origin,placement,affected,triangles,vertex_bytes,rebuild_ms,column_ms,full_triangles);fflush(stdout);
  }
  MeshLimits cancel;cancel.cancel=[](void*){return true;};auto failed=build_world_surface(w,origin,origin,32,cancel,64,96);
  if(failed.status!=MeshStatus::cancelled||!failed.geometry.p.empty()||!failed.normals.values.empty())return 13;
  w.release();
 }
 // Edits in another vertical brick may advance validity; overlapping edits may not.
 World edits;edits.init();
 for(int overlap=0;overlap<2;overlap++){
  SnapshotWorker worker(3*1024*1024,32*1024*1024);
  if(!worker.submit(edits,1280,1280,32,7,8,nullptr,0,32))return 21;
  V3 p{1296,float(overlap?16:96),1296},lo,hi;int changes=0,previous=edits.revision;
  bool changed=edits.edit(p,p,2,0,false,1,lo,hi,changes);
  if(!changed)changed=edits.edit(p,p,2,0,true,1,lo,hi,changes);
  if(!changed)return 22;
  worker.observe_density_edit(previous,edits.revision,lo,hi);
  bool received=false,correct=false;double deadline=now()+5000;
  while(!received&&now()<deadline){
   worker.consume_surface(7,edits.revision,[&](u64,u64,int,bool stale,const Result&r,const NormalResult&n){received=true;correct=stale==bool(overlap)&&r.y_begin==0&&r.y_end==32&&(stale?(r.p.empty()&&n.values.empty()):r.status==MeshStatus::ok);});
   if(!received)std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  worker.stop();if(!received||!correct)return 23;
 }
 edits.release();
 World dense;dense.init();
 for(int y=0;y<=16;y++)for(int z=80;z<=82;z++)for(int x=80;x<=82;x++)if(!dense.ensure(x,y,z))return 24;
 SparseRegionSnapshot full,bounded;
 if(full.capture(dense,1280,1280,32,MeshLimits{},true)!=MeshStatus::ok||bounded.capture(dense,1280,1280,32,MeshLimits{},true,32,64)!=MeshStatus::ok)return 25;
 if(full.lookups()!=153||bounded.lookups()!=27||full.bytes()-bounded.bytes()!=size_t(126)*PAGE_SAMPLES*sizeof(i16))return 26;
 printf("{\"kind\":\"capture\",\"full_lookups\":%d,\"bounded_lookups\":%d,\"full_bytes\":%zu,\"bounded_bytes\":%zu}\n",full.lookups(),bounded.lookups(),full.bytes(),bounded.bytes());
 dense.release();
 return 0;
}
