// Isolated geometry prototype. Not linked into the game or advertised as an addon.
#include "core.h"
#include <array>
#include <vector>
#include <unordered_map>
#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstdio>
#include <string>
#include <cstring>
#include <thread>
#include <mutex>
#include <condition_variable>

static double now(){return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();}
#include "experimental/world_region_sampler.hpp"
using namespace terraforest::experimental;

static void build(World&w,int x0,int z0,int size,const std::string&file){
 int n=size+1;
 std::vector<float> field(size_t(n)*n*257);
 std::vector<float> reference(field.size());
 auto index=[&](int x,int y,int z){return x+n*(z+n*y);};
 auto quantized_density=[](float d){float v=clampf(d,-SDF_BAND,SDF_BAND)*SDF_SCALE;int q=int(v>=0?v+.5f:v-.5f);return q?float(q)/SDF_SCALE:.5f/SDF_SCALE;};
 double begin=now();
 int zeros=0;
 for(int y=0;y<=256;y++)for(int z=0;z<=size;z++)for(int x=0;x<=size;x++){
  float value=clampf(w.sample(x0+x,y,z0+z),-SDF_BAND,SDF_BAND)*SDF_SCALE;
  int quantized=int(value>=0?value+.5f:value-.5f);
  if(!quantized)zeros++;
  // Experimental convention: zero is exterior, displaced by half a quantization
  // unit to avoid placing multiple intersections exactly on a lattice corner.
  reference[index(x,y,z)]=quantized?float(quantized)/SDF_SCALE:.5f/SDF_SCALE;
 }
 double reference_sampled=now();
 constexpr int np=WORLD/PAGE+1;
 for(int z=0;z<=size;z++)for(int x=0;x<=size;x++){
  int wx=x0+x,wz=z0+z;
  if(wx<0||wx>WORLD||wz<0||wz>WORLD){for(int y=0;y<=256;y++)field[index(x,y,z)]=SDF_BAND;continue;}
  float h=w.height(float(wx),float(wz));
  for(int py=0;py<=16;py++){
   u32 key=u32((wx>>4)+np*((wz>>4)+np*py))+1;
   int page_index=w.pages_by_key.get(key);
   for(int y=py*16;y<=imn(256,py*16+15);y++){
    float value=page_index<0?w.base({float(wx),float(y),float(wz)},h):float(w.pages[page_index].d[(wx&15)+16*((wz&15)+16*(y&15))])/SDF_SCALE;
    field[index(x,y,z)]=quantized_density(value);
   }
  }
 }
 double sampled=now();
 if(field!=reference){fprintf(stderr,"Column sampler disagrees with authoritative samples\n");std::exit(5);}
 Result result,control;double meshing_ms=0,control_ms=0;
 std::vector<double> scan_times,control_times;
 // Paired same-field control; alternate order between fixtures to expose bias.
 static int ordinal=0;
 for(int repetition=0;repetition<5;repetition++){
 for(int pass=0;pass<2;pass++){
  bool scan=((ordinal+repetition+pass)%2)==0;double tick=now();
  Result output=mesh_field(field,x0,z0,size,scan);
  double elapsed=now()-tick;
  if(scan){result=std::move(output);scan_times.push_back(elapsed);}
  else{control=std::move(output);control_times.push_back(elapsed);}
 }
 if(result.indices!=control.indices||result.p.size()!=control.p.size()||std::memcmp(result.p.data(),control.p.data(),result.p.size()*sizeof(V3))){fprintf(stderr,"Slab edge retirement changed geometry\n");std::exit(6);}
 }
 ordinal++;
 auto median=[](std::vector<double> values){std::sort(values.begin(),values.end());return values[values.size()/2];};
 meshing_ms=median(scan_times);control_ms=median(control_times);
 double stream_begin=now();
 Result streamed=build_world_region(w,x0,z0,size);
 double streamed_ms=now()-stream_begin;
 if(streamed.status!=MeshStatus::ok||streamed.indices!=result.indices||streamed.p.size()!=result.p.size()||std::memcmp(streamed.p.data(),result.p.data(),result.p.size()*sizeof(V3))){fprintf(stderr,"Rolling density field changed geometry\n");std::exit(10);}
 WorldRegionSampler rolling(w,x0,z0,size);
 for(int y=0;y<256;y++){
  const float*planes=rolling.layers(y);
  if(!planes||std::memcmp(planes,reference.data()+size_t(y)*n*n,size_t(n)*n*2*sizeof(float)))return std::exit(9);
 }
 auto residual=[&](V3 p){
  int x=imn(size-1,imx(0,fl(p.x)-x0)),z=imn(size-1,imx(0,fl(p.z)-z0)),y=imn(255,imx(0,fl(p.y)));
  double dx=p.x-x0-x,dy=p.y-y,dz=p.z-z0-z,value=0;
  for(int k=0;k<8;k++){
   float d=field[index(x+(k&1),y+((k>>1)&1),z+((k>>2)&1))];
   if(d==.5f/SDF_SCALE)d=0; // Compare against original quantized field, not biased zeros.
   value+=d*(k&1?dx:1-dx)*(k&2?dy:1-dy)*(k&4?dz:1-dz);
  }
  return value<0?-value:value;
 };
 double vertex_error=0,centroid_error=0;
 for(V3 p:result.p)vertex_error=std::max(vertex_error,residual(p));
 for(size_t i=0;i<result.indices.size();i+=3){V3 p=(result.p[result.indices[i]]+result.p[result.indices[i+1]]+result.p[result.indices[i+2]])/3.f;centroid_error=std::max(centroid_error,residual(p));}
 FILE*f=fopen(file.c_str(),"wb");if(!f)std::exit(2);
 u32 counts[2]={u32(result.p.size()),u32(result.indices.size())};
 fwrite(counts,4,2,f);fwrite(result.p.data(),sizeof(V3),result.p.size(),f);fwrite(result.indices.data(),4,result.indices.size(),f);fclose(f);
 printf("{\"size\":%d,\"x\":%d,\"z\":%d,\"reference_sampling_ms\":%.6f,\"sampling_ms\":%.6f,\"meshing_ms\":%.6f,\"control_meshing_ms\":%.6f,\"mesh_parity\":true,\"sample_parity\":true,\"vertices\":%zu,\"triangles\":%zu,\"zero_samples\":%d,\"max_vertex_field_residual\":%.8f,\"max_centroid_field_residual\":%.8f,\"meshing_samples_ms\":[",size,x0,z0,reference_sampled-begin,sampled-reference_sampled,meshing_ms,control_ms,result.p.size(),result.indices.size()/3,zeros,vertex_error,centroid_error);
 for(size_t i=0;i<scan_times.size();i++)printf("%s%.6f",i?",":"",scan_times[i]);
 printf("],\"control_meshing_samples_ms\":[");
 for(size_t i=0;i<control_times.size();i++)printf("%s%.6f",i?",":"",control_times[i]);
 printf("],\"peak_crossings\":%zu,\"control_peak_crossings\":%zu,\"peak_buckets\":%zu,\"control_peak_buckets\":%zu,\"streamed_parity\":true,\"streamed_total_ms\":%.6f,\"density_plane_bytes\":%zu,\"sampler_payload_bytes\":%zu,\"full_field_bytes\":%zu}\n",result.peak_crossings,control.peak_crossings,result.peak_buckets,control.peak_buckets,streamed_ms,rolling.planes.size()*sizeof(float),rolling.payload_bytes(),field.size()*sizeof(float));
}
int main(int argc,char**argv){
 if(argc!=2)return 2;
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;
 // Adversarial vertical density alternation: crossings throughout all 256 layers.
 // This is a storage/parity control, not a physically representative terrain.
 {
  const int size=8,n=9;std::vector<float>field(size_t(n)*n*257);
  for(int y=0;y<=256;y++)for(int z=0;z<n;z++)for(int x=0;x<n;x++)field[x+n*(z+n*y)]=(y&1)?-1.f:1.f;
  Result rolling=mesh_field(field,1280,1280,size,true),retained=mesh_field(field,1280,1280,size,false);
  if(rolling.indices!=retained.indices||rolling.p.size()!=retained.p.size()||std::memcmp(rolling.p.data(),retained.p.data(),rolling.p.size()*sizeof(V3))||rolling.peak_crossings>=retained.peak_crossings)return 8;
  fprintf(stderr,"{\"name\":\"256 alternating layers\",\"mesh_parity\":true,\"size\":8,\"peak_crossings\":%zu,\"control_peak_crossings\":%zu,\"peak_buckets\":%zu,\"control_peak_buckets\":%zu}\n",rolling.peak_crossings,retained.peak_crossings,rolling.peak_buckets,retained.peak_buckets);
  auto empty_failure=[](const Result&r,MeshStatus status){return r.status==status&&r.p.empty()&&r.indices.empty()&&r.crossings.empty()&&r.p.capacity()==0&&r.indices.capacity()==0;};
  struct Allocations{int fail=0,calls=0,live=0;};
  auto allocator=[](Allocations&state){
   BufferAllocator hooks;hooks.context=&state;
   hooks.allocate=[](void*p,size_t bytes)->void*{auto&s=*static_cast<Allocations*>(p);if(++s.calls==s.fail)return nullptr;void*memory=std::malloc(bytes);if(memory)s.live++;return memory;};
   hooks.release=[](void*p,void*memory){auto&s=*static_cast<Allocations*>(p);s.live--;std::free(memory);};
   return hooks;
  };
  Allocations allocation_baseline;
  {
   MeshLimits limits;limits.output_allocator=allocator(allocation_baseline);
   Result output=mesh_field(field,1280,1280,size,true,limits);
   if(output.status!=MeshStatus::ok||output.indices!=rolling.indices||output.p.size()!=rolling.p.size()||std::memcmp(output.p.data(),rolling.p.data(),rolling.p.size()*sizeof(V3)))return 28;
  }
  if(allocation_baseline.live||allocation_baseline.calls<4)return 29;
  for(int fail=1;fail<=allocation_baseline.calls;fail++){
   Allocations state;state.fail=fail;MeshLimits limits;limits.output_allocator=allocator(state);
   Result output=mesh_field(field,1280,1280,size,true,limits);
   if(!empty_failure(output,MeshStatus::allocation_failed)||state.live||state.calls!=fail)return 30;
  }
  // Allocation failure must not poison a later build or allocator ownership on move.
  Allocations recovery;
  {
   MeshLimits limits;limits.output_allocator=allocator(recovery);
   Result output=mesh_field(field,1280,1280,size,true,limits);
   Result moved=std::move(output);
   if(moved.status!=MeshStatus::ok||!output.p.empty()||!output.indices.empty()||moved.indices!=rolling.indices||moved.p.size()!=rolling.p.size()||std::memcmp(moved.p.data(),rolling.p.data(),rolling.p.size()*sizeof(V3)))return 31;
  }
  if(recovery.live)return 32;
  fprintf(stderr,"{\"name\":\"output allocation failures\",\"injected_failures\":%d,\"empty_failures\":true,\"no_live_buffers\":true,\"retry_and_move_parity\":true}\n",allocation_baseline.calls);
  int invalid_cases=0;
  for(auto region:std::vector<std::array<int,3>>{{-1,1280,8},{1280,-1,8},{1993,1280,8},{1280,1993,8},{std::numeric_limits<int>::max(),1280,8},{1280,1280,0},{1280,1280,-1},{1280,1280,33},{1280,1280,std::numeric_limits<int>::max()}}){
   int calls=0;
   Result invalid=mesh_layers(region[0],region[1],region[2],true,[&](int){calls++;return field.data();});
   if(calls||!empty_failure(invalid,MeshStatus::invalid_input))return 17;
   invalid_cases++;
  }
  for(bool vertices:{true,false}){
   MeshLimits oversized;if(vertices)oversized.vertices=size_t(std::numeric_limits<u32>::max())+1;else oversized.indices=size_t(std::numeric_limits<u32>::max())+1;
   Result invalid=mesh_field(field,1280,1280,size,true,oversized);
   if(!empty_failure(invalid,MeshStatus::invalid_input))return 18;
   invalid_cases++;
  }
  std::vector<float>short_field(1,1.f);
  if(!empty_failure(mesh_field(short_field,1280,1280,size,true),MeshStatus::invalid_input))return 19;
  invalid_cases++;
  if(!empty_failure(mesh_layers(1280,1280,size,true,[](int)->const float*{return nullptr;}),MeshStatus::invalid_input))return 20;
  invalid_cases++;
  for(float bad:{std::numeric_limits<float>::quiet_NaN(),std::numeric_limits<float>::infinity()}){
   auto invalid_field=field;invalid_field[size_t(n)*n*100]=bad;
   Result invalid=mesh_field(invalid_field,1280,1280,size,true);
   if(!empty_failure(invalid,MeshStatus::invalid_input)||!invalid.peak_vertices)return 21;
   invalid_cases++;
  }
  fprintf(stderr,"{\"name\":\"validated region interface\",\"invalid_cases\":%d,\"empty_failure\":true,\"invalid_region_skips_provider\":true}\n",invalid_cases);
  for(size_t cap:{size_t(0),size_t(1),size_t(10),rolling.p.size()-1}){
   MeshLimits limits;limits.vertices=cap;Result failed=mesh_field(field,1280,1280,size,true,limits);
   if(!empty_failure(failed,MeshStatus::output_limit)||failed.peak_vertices>cap)return 11;
   fprintf(stderr,"{\"name\":\"vertex limit\",\"limit\":%zu,\"peak\":%zu,\"empty_failure\":true}\n",cap,failed.peak_vertices);
  }
  for(size_t cap:{size_t(0),size_t(2),size_t(30),rolling.indices.size()-1}){
   MeshLimits limits;limits.indices=cap;Result failed=mesh_field(field,1280,1280,size,true,limits);
   if(!empty_failure(failed,MeshStatus::output_limit)||failed.peak_indices>cap)return 12;
   fprintf(stderr,"{\"name\":\"index limit\",\"limit\":%zu,\"peak\":%zu,\"empty_failure\":true}\n",cap,failed.peak_indices);
  }
  struct Cancel{int at,calls=0;};
  for(int at:{1,5,1000}){
   Cancel state{at};MeshLimits limits;limits.context=&state;limits.cancel=[](void*p){auto&s=*static_cast<Cancel*>(p);return ++s.calls>=s.at;};
   Result failed=mesh_field(field,1280,1280,size,true,limits);
   if(!empty_failure(failed,MeshStatus::cancelled)||state.calls!=at||(at>1&&failed.peak_vertices==0))return 13;
   fprintf(stderr,"{\"name\":\"cancellation\",\"at\":%d,\"calls\":%d,\"peak_vertices\":%zu,\"empty_failure\":true}\n",at,state.calls,failed.peak_vertices);
  }
  MeshLimits exact;exact.vertices=rolling.p.size();exact.indices=rolling.indices.size();
  Result recovered=mesh_field(field,1280,1280,size,true,exact);
  if(recovered.status!=MeshStatus::ok||recovered.indices!=rolling.indices||recovered.p.size()!=rolling.p.size()||std::memcmp(recovered.p.data(),rolling.p.data(),rolling.p.size()*sizeof(V3))||recovered.p.capacity()>exact.vertices||recovered.indices.capacity()>exact.indices)return 14;
  fprintf(stderr,"{\"name\":\"exact output limits and recovery\",\"mesh_parity\":true}\n");
  // Use the same per-world atomic epoch API as the native terrain bridge.
  // A synchronization barrier makes interruption happen after geometry exists,
  // rather than relying on a sleep or hoping the worker has started.
  BuildControl control_a,control_b;World world_a,world_b;
  world_a.build_control=&control_a;world_b.build_control=&control_b;
  struct HeldEpoch{
   const World*world;u32 expected;std::mutex mutex;std::condition_variable condition;
   bool entered=false,resume=false;int calls=0;
  } held{&world_a,terrain_build_epoch(&world_a)};
  MeshLimits interrupted;interrupted.context=&held;
  interrupted.cancel=[](void*p){
   auto&s=*static_cast<HeldEpoch*>(p);
   if(++s.calls==5){
    std::unique_lock<std::mutex>lock(s.mutex);s.entered=true;s.condition.notify_one();
    s.condition.wait(lock,[&]{return s.resume;});
   }
   return terrain_build_epoch(s.world)!=s.expected;
  };
  Result cancelled_result;
  std::thread worker([&]{cancelled_result=mesh_field(field,1280,1280,size,true,interrupted);});
  bool entered=false;
  {
   std::unique_lock<std::mutex>lock(held.mutex);
   entered=held.condition.wait_for(lock,std::chrono::seconds(5),[&]{return held.entered;});
  }
  const u32 other_epoch=terrain_build_epoch(&world_b);
  terrain_cancel_builds(&world_a);
  struct Epoch{const World*world;u32 expected;};
  Epoch unaffected{&world_b,other_epoch};MeshLimits other_limits;other_limits.context=&unaffected;
  other_limits.cancel=[](void*p){auto&s=*static_cast<Epoch*>(p);return terrain_build_epoch(s.world)!=s.expected;};
  Result other=mesh_field(field,1280,1280,size,true,other_limits);
  {
   std::lock_guard<std::mutex>lock(held.mutex);held.resume=true;
  }
  held.condition.notify_one();worker.join();
  if(!entered||!empty_failure(cancelled_result,MeshStatus::cancelled)||cancelled_result.peak_vertices==0||other.status!=MeshStatus::ok||other.indices!=rolling.indices||other.p.size()!=rolling.p.size()||std::memcmp(other.p.data(),rolling.p.data(),rolling.p.size()*sizeof(V3))||terrain_build_epoch(&world_b)!=other_epoch)return 15;
  Epoch refreshed{&world_a,terrain_build_epoch(&world_a)};MeshLimits refreshed_limits=other_limits;refreshed_limits.context=&refreshed;
  Result retried=mesh_field(field,1280,1280,size,true,refreshed_limits);
  if(retried.status!=MeshStatus::ok||retried.indices!=rolling.indices||retried.p.size()!=rolling.p.size()||std::memcmp(retried.p.data(),rolling.p.data(),rolling.p.size()*sizeof(V3)))return 16;
  fprintf(stderr,"{\"name\":\"threaded per-world epoch cancellation\",\"cancelled_after_vertices\":%zu,\"callback_calls\":%d,\"discarded\":true,\"other_world_unchanged\":true,\"retry_parity\":true}\n",cancelled_result.peak_vertices,held.calls);
 }
 World w;w.init(1703);
 {
  auto empty=[](const Result&r,MeshStatus status){return r.status==status&&r.p.empty()&&r.indices.empty()&&r.crossings.empty();};
  struct Stop{int at,calls=0;};
  for(int at:{1,5,40,100,1000}){
   Stop stop{at};MeshLimits limits;limits.context=&stop;limits.cancel=[](void*p){auto&s=*static_cast<Stop*>(p);return ++s.calls>=s.at;};
   Result failed=build_world_region(w,1280,1280,16,limits);
   if(!empty(failed,MeshStatus::cancelled)||stop.calls!=at)return 22;
   fprintf(stderr,"{\"name\":\"world region entry\",\"case\":\"cancel\",\"at\":%d,\"passed\":true}\n",at);
  }
  World uninitialized;
  if(!empty(build_world_region(uninitialized,1280,1280,16),MeshStatus::invalid_input))return 23;
  fprintf(stderr,"{\"name\":\"world region entry\",\"case\":\"uninitialized world\",\"passed\":true}\n");
  if(!empty(build_world_region(w,-1,1280,16),MeshStatus::invalid_input))return 24;
  fprintf(stderr,"{\"name\":\"world region entry\",\"case\":\"invalid region\",\"passed\":true}\n");
  MeshLimits zero;zero.vertices=0;
  if(!empty(build_world_region(w,1280,1280,16,zero),MeshStatus::output_limit))return 25;
  fprintf(stderr,"{\"name\":\"world region entry\",\"case\":\"output limit\",\"passed\":true}\n");
  for(int kind=0;kind<3;kind++){
   WorldRegionSampler sampler(w,1280,1280,16);
   if(kind==1)sampler.layers(0);
   if(sampler.layers(kind==0?1:(kind==1?0:256))||sampler.status!=MeshStatus::invalid_input)return 26;
   fprintf(stderr,"{\"name\":\"world region entry\",\"case\":\"invalid plane sequence\",\"kind\":%d,\"passed\":true}\n",kind);
  }
  Result first=build_world_region(w,1280,1280,16),second=build_world_region(w,1280,1280,16);
  if(first.status!=MeshStatus::ok||second.status!=MeshStatus::ok||first.indices!=second.indices||first.p.size()!=second.p.size()||std::memcmp(first.p.data(),second.p.data(),first.p.size()*sizeof(V3)))return 27;
  fprintf(stderr,"{\"name\":\"world region entry\",\"case\":\"successful retry repeatability\",\"passed\":true}\n");
 }
 // Sampler-only world-edge controls; no global mesh IDs are formed outside world.
 for(auto origin:std::array<std::array<int,2>,3>{{{{0,0}},{{-8,0}},{{1992,1992}}}}){
  const int size=16,n=17;std::vector<float>reference(size_t(n)*n*257);
  for(int y=0;y<=256;y++)for(int z=0;z<n;z++)for(int x=0;x<n;x++)reference[x+n*(z+n*y)]=density_value(w.sample(origin[0]+x,y,origin[1]+z));
  WorldRegionSampler rolling(w,origin[0],origin[1],size);
  for(int y=0;y<256;y++){
   const float*planes=rolling.layers(y);
   if(!planes||std::memcmp(planes,reference.data()+size_t(y)*n*n,size_t(n)*n*2*sizeof(float)))return 9;
  }
  fprintf(stderr,"{\"name\":\"world-edge sampler\",\"x\":%d,\"z\":%d,\"sample_parity\":true,\"samples\":%zu}\n",origin[0],origin[1],reference.size());
 }
 for(int site=0;site<3;site++){
  int x=site==0?960:1280,z=site==0?960:1280;
  if(site==2){V3 p={1296,w.height(1296,1296),1296},lo,hi;int changes=0;if(!w.edit(p,p,5,0,false,1,lo,hi,changes)||!changes)return 3;}
  auto path=[&](int ox,int oz,int n){return std::string(argv[1])+"/"+std::to_string(site)+"_"+std::to_string(ox)+"_"+std::to_string(oz)+"_"+std::to_string(n)+".bin";};
  build(w,x,z,32,path(x,z,32));
  for(int dz:{0,16})for(int dx:{0,16})build(w,x+dx,z+dz,16,path(x+dx,z+dz,16));
 }
 w.release();return tr_oom?4:0;
}
