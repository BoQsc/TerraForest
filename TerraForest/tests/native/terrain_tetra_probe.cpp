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

static double now(){return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();}
struct Sample{V3 p;float d;u32 id;};
enum class MeshStatus{ok,output_limit,cancelled};
struct MeshLimits{
 size_t vertices=1000000,indices=3000000;
 bool(*cancel)(void*)=nullptr;void*context=nullptr;
 bool cancelled()const{return cancel&&cancel(context);}
};
struct Result{
 std::vector<V3> p;std::vector<u32> indices;
 std::unordered_map<u64,u32> crossings;
 size_t peak_crossings=0,peak_buckets=0;
 size_t peak_vertices=0,peak_indices=0;
 MeshLimits limits;MeshStatus status=MeshStatus::ok;
 void discard(MeshStatus why){
  status=why;std::vector<V3>().swap(p);std::vector<u32>().swap(indices);
  std::unordered_map<u64,u32>().swap(crossings);
 }
 template<class T>static void grow(std::vector<T>&v,size_t need,size_t limit){
  if(need>v.capacity())v.reserve(std::min(limit,std::max(need,std::max(size_t(16),v.capacity()*2))));
 }
 u32 intersection(Sample a,Sample b){
  if(status!=MeshStatus::ok)return 0;
  if(a.id>b.id)std::swap(a,b);
  u64 key=(u64(a.id)<<32)|b.id;
  auto found=crossings.find(key);if(found!=crossings.end())return found->second;
  if(p.size()>=limits.vertices){status=MeshStatus::output_limit;return 0;}
  // Canonical endpoint order makes adjacent independently built regions agree.
  double t=double(a.d)/(double(a.d)-b.d);
  V3 point={float(a.p.x+(b.p.x-a.p.x)*t),float(a.p.y+(b.p.y-a.p.y)*t),float(a.p.z+(b.p.z-a.p.z)*t)};
  grow(p,p.size()+1,limits.vertices);
  u32 id=u32(p.size());p.push_back(point);crossings.emplace(key,id);
  peak_vertices=std::max(peak_vertices,p.size());
  peak_crossings=std::max(peak_crossings,crossings.size());
  peak_buckets=std::max(peak_buckets,crossings.bucket_count());return id;
 }
 void tri(u32 a,u32 b,u32 c,V3 outward){
  if(status!=MeshStatus::ok)return;
  if(indices.size()>limits.indices||limits.indices-indices.size()<3){status=MeshStatus::output_limit;return;}
  if(dot(cross(p[b]-p[a],p[c]-p[a]),outward)<0)std::swap(b,c);
  grow(indices,indices.size()+3,limits.indices);
  indices.insert(indices.end(),{a,b,c});
  peak_indices=std::max(peak_indices,indices.size());
 }
 void tetra(const Sample*s,const int*q){
  int in[4],out[4],ni=0,no=0;V3 ci{},co{};
  for(int i=0;i<4;i++){int k=q[i];if(s[k].d<0){in[ni++]=k;ci=ci+s[k].p;}else{out[no++]=k;co=co+s[k].p;}}
  if(!ni||!no)return;
  V3 direction=co/float(no)-ci/float(ni);
  if(ni==1||no==1){
   int single=ni==1?in[0]:out[0];int*other=ni==1?out:in;
   tri(intersection(s[single],s[other[0]]),intersection(s[single],s[other[1]]),intersection(s[single],s[other[2]]),direction);
  }else{
   u32 ac=intersection(s[in[0]],s[out[0]]),ad=intersection(s[in[0]],s[out[1]]);
   u32 bc=intersection(s[in[1]],s[out[0]]),bd=intersection(s[in[1]],s[out[1]]);
   tri(ac,ad,bd,direction);tri(ac,bd,bc,direction);
  }
 }
};

template<class Layers>
static Result mesh_layers(int x0,int z0,int size,bool retire_edges,Layers&&layers,const MeshLimits&limits=MeshLimits{}){
 int n=size+1;
 auto index=[&](int x,int y,int z){return x+n*(z+n*y);};
 Result result;result.limits=limits;
 constexpr int tets[6][4]={{0,1,3,7},{0,3,2,7},{0,2,6,7},{0,6,4,7},{0,4,5,7},{0,5,1,7}};
 for(int y=0;y<256;y++){
 if(limits.cancelled()){result.discard(MeshStatus::cancelled);return result;}
 const float*field=layers(y);
 for(int z=0;z<size;z++){
 if(limits.cancelled()){result.discard(MeshStatus::cancelled);return result;}
 for(int x=0;x<size;x++){
  {
   unsigned mask=0;
   for(int k=0;k<8;k++)mask|=unsigned(field[index(x+(k&1),(k>>1)&1,z+((k>>2)&1))]<0)<<k;
   if(mask==0||mask==255)continue;
  }
  Sample s[8];int negative=0;
  for(int k=0;k<8;k++){
   int sx=x+(k&1),sy=y+((k>>1)&1),sz=z+((k>>2)&1);
   s[k]={{float(x0+sx),float(sy),float(z0+sz)},field[index(sx,sy-y,sz)],u32(x0+sx+2049*((z0+sz)+2049*sy))};
   negative+=s[k].d<0;
  }
  if(negative==0||negative==8)continue;
  for(const auto&t:tets){
   result.tetra(s,t);
   if(result.status!=MeshStatus::ok){result.discard(result.status);return result;}
  }
 }
 }
 if(limits.cancelled()){result.discard(MeshStatus::cancelled);return result;}
  if(retire_edges){
   // A later cell can only reuse edges on this layer's top plane. Canonical
   // endpoint IDs increase with Y, so the smaller endpoint determines survival.
   const u32 next_plane=u32(y+1)*2049u*2049u;
   for(auto it=result.crossings.begin();it!=result.crossings.end();){
    if(u32(it->first>>32)<next_plane)it=result.crossings.erase(it);else ++it;
   }
  }
 }
 if(retire_edges&&result.peak_crossings>size_t(36)*size*size){fprintf(stderr,"Crossing map exceeded single-slab edge bound\n");std::exit(7);}
 return result;
}

static Result mesh_field(const std::vector<float>&field,int x0,int z0,int size,bool retire_edges,const MeshLimits&limits=MeshLimits{}){
 size_t plane=size_t(size+1)*(size+1);
 return mesh_layers(x0,z0,size,retire_edges,[&](int y){return field.data()+size_t(y)*plane;},limits);
}

static float density_value(float d){
 float v=clampf(d,-SDF_BAND,SDF_BAND)*SDF_SCALE;int q=int(v>=0?v+.5f:v-.5f);
 return q?float(q)/SDF_SCALE:.5f/SDF_SCALE;
}

struct RollingField{
 World&w;int x0,z0,n,page_y=-1;
 size_t plane;
 std::vector<float> planes,heights;
 std::vector<int> page_indices;
 const std::vector<float>*expected;
 RollingField(World&world,int x,int z,int size,const std::vector<float>*reference):w(world),x0(x),z0(z),n(size+1),plane(size_t(n)*n),planes(plane*2),heights(plane),page_indices(plane),expected(reference){
  for(int dz=0;dz<n;dz++)for(int dx=0;dx<n;dx++)heights[dx+n*dz]=w.height(float(x0+dx),float(z0+dz));
  fill(0,planes.data());fill(1,planes.data()+plane);
 }
 void fill(int y,float*out){
  constexpr int np=WORLD/PAGE+1;
  int py=y>>4;
  if(py!=page_y){
   for(int z=0;z<n;z++)for(int x=0;x<n;x++){
    int wx=x0+x,wz=z0+z;
    page_indices[x+n*z]=(wx<0||wx>WORLD||wz<0||wz>WORLD)?-2:w.pages_by_key.get(u32((wx>>4)+np*((wz>>4)+np*py))+1);
   }
   page_y=py;
  }
  for(int z=0;z<n;z++)for(int x=0;x<n;x++){
   int wx=x0+x,wz=z0+z,at=x+n*z,pi=page_indices[at];
   float d=pi==-2?SDF_BAND:(pi<0?w.base({float(wx),float(y),float(wz)},heights[at]):float(w.pages[pi].d[(wx&15)+16*((wz&15)+16*(y&15))])/SDF_SCALE);
   out[at]=density_value(d);
  }
  if(expected&&std::memcmp(out,expected->data()+size_t(y)*plane,plane*sizeof(float))){fprintf(stderr,"Rolling sampler differs from full field\n");std::exit(9);}
 }
 const float*layers(int y){
  if(y){std::copy(planes.begin()+plane,planes.end(),planes.begin());fill(y+1,planes.data()+plane);}
  return planes.data();
 }
 size_t payload_bytes()const{return (planes.size()+heights.size())*sizeof(float)+page_indices.size()*sizeof(int);}
};

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
 RollingField rolling(w,x0,z0,size,&reference);
 Result streamed=mesh_layers(x0,z0,size,true,[&](int y){return rolling.layers(y);});
 double streamed_ms=now()-stream_begin;
 if(streamed.indices!=result.indices||streamed.p.size()!=result.p.size()||std::memcmp(streamed.p.data(),result.p.data(),result.p.size()*sizeof(V3))){fprintf(stderr,"Rolling density field changed geometry\n");std::exit(10);}
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
 }
 World w;w.init(1703);
 // Sampler-only world-edge controls; no global mesh IDs are formed outside world.
 for(auto origin:std::array<std::array<int,2>,3>{{{{0,0}},{{-8,0}},{{1992,1992}}}}){
  const int size=16,n=17;std::vector<float>reference(size_t(n)*n*257);
  for(int y=0;y<=256;y++)for(int z=0;z<n;z++)for(int x=0;x<n;x++)reference[x+n*(z+n*y)]=density_value(w.sample(origin[0]+x,y,origin[1]+z));
  RollingField rolling(w,origin[0],origin[1],size,&reference);
  for(int y=0;y<256;y++)rolling.layers(y);
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
