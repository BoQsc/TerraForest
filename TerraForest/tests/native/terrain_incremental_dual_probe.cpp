// SPDX-License-Identifier: 0BSD
#include "core.h"
#include "dual_probe_world_field.hpp"
#include "dual_probe_audit.hpp"
#include <chrono>
#include <cstdio>
using namespace dual_probe;
static double now(){return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();}
template<class Field,class Edit>static int run(const char*kind,int extent,Field field,Edit edit){
 double start=now();dual_probe::Mesh<Field> mesh(field,extent);double cold=now()-start;int failures=0;bool ownership=mesh.valid_ownership();
 for(int iteration=0;iteration<4;iteration++){
  double edit_ms=0,oracle_ms=0;bool equal=true,changed=true;
  if(iteration){Box box;changed=edit(iteration,box);start=now();mesh.edit(box);edit_ms=now()-start;start=now();dual_probe::Mesh<Field> fresh(field,extent);oracle_ms=now()-start;equal=mesh.same(fresh);}
  auto a=audit(mesh);size_t unmapped=mesh.unmapped_crossings(),unrepresented=mesh.unrepresented_loops();bool passed=ownership&&mesh.valid_storage()&&!unmapped&&!unrepresented&&equal&&changed&&!(a.open||a.overused||a.winding||a.degenerate||a.links);failures+=!passed;
  printf("{\"kind\":\"%s\",\"extent\":%d,\"edit\":%d,\"leaves\":%zu,\"shared_edges\":%zu,\"triangles\":%zu,\"unmapped_crossings\":%zu,\"unrepresented_boundary_loops\":%zu,\"cold_ms\":%.6f,\"cold_stages_ms\":[%.6f,%.6f,%.6f,%.6f],\"edge_payload_bytes\":%zu,\"dependency_payload_bytes\":%zu,\"fingerprint\":\"%016llx\",\"local_update_ms\":%.6f,\"oracle_ms\":%.6f,\"candidate_edges\":%zu,\"reevaluated_edges\":%zu,\"refitted_cells\":%zu,\"affected_faces\":%zu,\"local_samples\":%zu,\"fresh_equal\":%s,\"edit_changed\":%s,\"internal_open_edges\":%d,\"overused_edges\":%d,\"winding_errors\":%d,\"degenerate_triangles\":%d,\"invalid_vertex_links\":%d,\"passed\":%s}\n",kind,extent,iteration,mesh.cells.size(),mesh.edge_count(),mesh.triangles(),unmapped,unrepresented,cold,mesh.cold_stages[0],mesh.cold_stages[1],mesh.cold_stages[2],mesh.cold_stages[3],mesh.edge_payload_bytes(),mesh.dependency_payload_bytes(),(unsigned long long)mesh.fingerprint(),edit_ms,oracle_ms,mesh.last.candidates,mesh.last.edges,mesh.last.cells,mesh.last.faces,mesh.last.samples,equal?"true":"false",changed?"true":"false",a.open,a.overused,a.winding,a.degenerate,a.links,passed?"true":"false");fflush(stdout);
 }return failures;
}
static int recycle(){
 bool carved=false;auto field=[&](P p){double distance=0;for(int k=0;k<3;k++)distance+=(p[k]-32)*(p[k]-32);distance=std::sqrt(distance);double d=std::max(-4.,std::min(4.,distance-12));return carved?std::max(d,2.5-distance):d;};
 dual_probe::Mesh<decltype(field)> mesh(field,64);uint64_t expected[2]={mesh.fingerprint(),0};size_t capacity=0;int failures=0;
 for(int i=0;i<64;i++){carved=(i%2)==0;mesh.edit({{25,25,25},{39,39,39}});uint64_t fingerprint=mesh.fingerprint();
  if(i==0){dual_probe::Mesh<decltype(field)> fresh(field,64);if(!mesh.same(fresh))failures++;expected[1]=fresh.fingerprint();}
  if(i==1)capacity=mesh.edge_payload_bytes();
  if(fingerprint!=expected[carved]||!mesh.valid_storage()||(i>1&&mesh.edge_payload_bytes()!=capacity))failures++;
 }
 printf("{\"kind\":\"crossing_reuse\",\"cycles\":64,\"slot_count\":%zu,\"free_slots\":%zu,\"steady_edge_capacity_bytes\":%zu,\"failures\":%d,\"passed\":%s}\n",mesh.crossings.size(),mesh.free_crossings.size(),capacity,failures,failures?"false":"true");return failures;
}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;int failures=0;
 for(int extent:{32,64,128}){
  std::vector<P> cuts;double center=extent*.5;
  auto field=[&](P p){double r=0;for(int k=0;k<3;k++)r+=(p[k]-center)*(p[k]-center);double d=std::max(-4.,std::min(4.,std::sqrt(r)-12));for(P c:cuts){r=0;for(int k=0;k<3;k++)r+=(p[k]-c[k])*(p[k]-c[k]);d=std::max(d,std::min(4.,2.5-std::sqrt(r)));}return d;};
  auto edit=[&](int n,Box&box){P c={center+(n>=2?8:0),center-(n==3?8:0),center+(n==3?8:0)};cuts.push_back(c);for(int k=0;k<3;k++){box.lo[k]=int(c[k])-7;box.hi[k]=int(c[k])+7;}return true;};
  failures+=run("sphere",extent,field,edit);
  World world;world.init();P anchor={1024,double(int(world.height(1024,1024))-1),1024};
  WorldField terrain{&world,{anchor[0]-center,anchor[1]-center,anchor[2]-center},{}};
  auto terrain_edit=[&](int n,Box&box){V3 p={float(anchor[0]+(n>=2?8:0)),float(anchor[1]-(n>=2?8:0)),float(anchor[2]+(n==3?8:0))},lo,hi;int changes=0;bool changed=world.edit(p,p,2.5f,0,false,1,lo,hi,changes);float low[3]={lo.x,lo.y,lo.z},high[3]={hi.x,hi.y,hi.z};for(int k=0;k<3;k++){box.lo[k]=int(std::floor(low[k]-anchor[k]+center));box.hi[k]=int(std::ceil(high[k]-anchor[k]+center));}return changed&&changes>0;};
  failures+=run("world",extent,terrain,terrain_edit);world.release();
 }failures+=recycle();return failures?1:0;
}
