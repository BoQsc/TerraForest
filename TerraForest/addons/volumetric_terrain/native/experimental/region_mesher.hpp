// SPDX-License-Identifier: 0BSD
// Experimental geometry-only mesher. Not registered in the game extension.
#pragma once
#include "../core.h"
#include "fallible_buffer.hpp"
#include "lattice_edge_table.hpp"
#include <vector>
#include <algorithm>
#include <cmath>
#include <limits>

namespace terraforest::experimental {
struct Sample{V3 p;float d;u32 id;};
enum class MeshStatus{ok,output_limit,cancelled,invalid_input,internal_error,allocation_failed};
struct MeshLimits{
 bool exact_zero_vertices=false; // Experimental alternative; default stays frozen.
 size_t vertices=1000000,indices=3000000;
 bool(*cancel)(void*)=nullptr;void*context=nullptr;
 BufferAllocator output_allocator;
 BufferAllocator sampler_allocator;
 BufferAllocator crossing_allocator;
 bool cancelled()const{return cancel&&cancel(context);}
};
struct Result{
 FallibleBuffer<V3> p;FallibleBuffer<u32> indices;
 LatticeEdgeTable crossings;
 FallibleBuffer<u32> zero_vertices;
 int origin_x=0,origin_z=0,width=0,y_begin=0,y_end=WORLD_Y;bool rolling_zeros=true;
 size_t collapsed_triangles=0;
 size_t peak_crossings=0,peak_table_slots=0;
 size_t peak_vertices=0,peak_indices=0;
 MeshLimits limits;MeshStatus status=MeshStatus::ok;
 void discard(MeshStatus why){
  status=why;p.clear();indices.clear();
  crossings.clear();
  zero_vertices.clear();
 }
 template<class T>static bool grow(FallibleBuffer<T>&v,size_t need,size_t limit){
  return need<=v.capacity()||v.reserve(std::min(limit,std::max(need,std::max(size_t(16),v.capacity()*2))));
 }
 u32 intersection(Sample a,Sample b){
  if(status!=MeshStatus::ok)return 0;
  if(a.id>b.id)std::swap(a,b);
  size_t slot=crossings.slot(a.id,b.id);
  if(slot==LatticeEdgeTable::invalid_slot){status=MeshStatus::internal_error;return 0;}
  if(limits.exact_zero_vertices&&(a.d==.5f/SDF_SCALE||b.d==.5f/SDF_SCALE)){
   const Sample&zero=a.d==.5f/SDF_SCALE?a:b;
   int y=int(zero.p.y),x=int(zero.p.x)-origin_x,z=int(zero.p.z)-origin_z;
   size_t at=size_t(rolling_zeros?(y&1):y)*width*width+z*width+x;
   if(zero_vertices[at]!=LatticeEdgeTable::absent)return zero_vertices[at];
   if(p.size()>=limits.vertices){status=MeshStatus::output_limit;return 0;}
   if(!grow(p,p.size()+1,limits.vertices)){status=MeshStatus::allocation_failed;return 0;}
   u32 id=u32(p.size());p.push_back(zero.p);zero_vertices[at]=id;
   peak_vertices=std::max(peak_vertices,p.size());return id;
  }
  u32 found=crossings.get(slot);if(found!=LatticeEdgeTable::absent)return found;
  if(p.size()>=limits.vertices){status=MeshStatus::output_limit;return 0;}
  // Canonical endpoint order makes adjacent independently built regions agree.
  double t=double(a.d)/(double(a.d)-b.d);
  V3 point={float(a.p.x+(b.p.x-a.p.x)*t),float(a.p.y+(b.p.y-a.p.y)*t),float(a.p.z+(b.p.z-a.p.z)*t)};
  if(!grow(p,p.size()+1,limits.vertices)){status=MeshStatus::allocation_failed;return 0;}
  u32 id=u32(p.size());p.push_back(point);crossings.put(slot,id);
  peak_vertices=std::max(peak_vertices,p.size());
  peak_crossings=std::max(peak_crossings,crossings.size());
  peak_table_slots=std::max(peak_table_slots,crossings.slots());return id;
 }
 void tri(u32 a,u32 b,u32 c,V3 outward){
  if(status!=MeshStatus::ok)return;
  if(limits.exact_zero_vertices&&(a==b||b==c||a==c)){collapsed_triangles++;return;}
  if(indices.size()>limits.indices||limits.indices-indices.size()<3){status=MeshStatus::output_limit;return;}
  if(dot(cross(p[b]-p[a],p[c]-p[a]),outward)<0)std::swap(b,c);
  if(!grow(indices,indices.size()+3,limits.indices)){status=MeshStatus::allocation_failed;return;}
  indices.push_back(a);indices.push_back(b);indices.push_back(c);
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

static bool valid_region(int x0,int z0,int size,const MeshLimits&limits){
 return size>=1&&size<=32&&x0>=0&&z0>=0&&x0<=WORLD-size&&z0<=WORLD-size&&
        limits.vertices<=std::numeric_limits<u32>::max()&&limits.indices<=std::numeric_limits<u32>::max()&&limits.output_allocator.allocate&&limits.output_allocator.release&&limits.sampler_allocator.allocate&&limits.sampler_allocator.release&&limits.crossing_allocator.allocate&&limits.crossing_allocator.release;
}
static bool valid_vertical_range(int begin,int end){return begin>=0&&begin<end&&end<=WORLD_Y;}

// Providers must return two contiguous (size+1)^2 planes for each absolute Y.
// Cell ownership is [y_begin,y_end); shared samples include y_end. Global edge
// IDs and canonical intersections are unchanged across independently built slabs.
// The caller owns immutable sample storage throughout the synchronous call.
template<class Layers>
static Result mesh_layers(int x0,int z0,int size,bool retire_edges,Layers&&layers,const MeshLimits&limits=MeshLimits{},int y_begin=0,int y_end=WORLD_Y){
 if(!valid_region(x0,z0,size,limits)||!valid_vertical_range(y_begin,y_end)){Result invalid;invalid.status=MeshStatus::invalid_input;return invalid;}
 int n=size+1;
 auto index=[&](int x,int y,int z){return x+n*(z+n*y);};
 Result result;result.limits=limits;result.p.set_allocator(limits.output_allocator);result.indices.set_allocator(limits.output_allocator);
 result.origin_x=x0;result.origin_z=z0;result.width=n;result.y_begin=y_begin;result.y_end=y_end;result.rolling_zeros=retire_edges;
 if(limits.cancelled()){result.discard(MeshStatus::cancelled);return result;}
 if(!result.crossings.initialize(x0,z0,size,retire_edges,limits.crossing_allocator)){result.discard(MeshStatus::allocation_failed);return result;}
 if(limits.exact_zero_vertices){
  result.zero_vertices.set_allocator(limits.crossing_allocator);
  if(!result.zero_vertices.resize(size_t(n)*n*(retire_edges?2:257))){result.discard(MeshStatus::allocation_failed);return result;}
  std::fill(result.zero_vertices.begin(),result.zero_vertices.end(),LatticeEdgeTable::absent);
 }
 constexpr int tets[6][4]={{0,1,3,7},{0,3,2,7},{0,2,6,7},{0,6,4,7},{0,4,5,7},{0,5,1,7}};
 for(int y=y_begin;y<y_end;y++){
 if(limits.cancelled()){result.discard(MeshStatus::cancelled);return result;}
 const float*field=layers(y);
 if(!field){result.discard(MeshStatus::invalid_input);return result;}
 for(size_t i=0;i<size_t(n)*n*2;i++)if(!std::isfinite(field[i])){result.discard(MeshStatus::invalid_input);return result;}
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
   result.crossings.retire(y);
   if(limits.exact_zero_vertices){size_t at=size_t(y&1)*n*n;std::fill(result.zero_vertices.begin()+at,result.zero_vertices.begin()+at+n*n,LatticeEdgeTable::absent);}
  }
 }
 if(retire_edges&&result.peak_crossings>size_t(36)*size*size){result.discard(MeshStatus::internal_error);}
 // Deduplication storage is scratch, not part of the returned mesh lifetime.
 result.crossings.clear();
 result.zero_vertices.clear();
 return result;
}

static Result mesh_field(const std::vector<float>&field,int x0,int z0,int size,bool retire_edges,const MeshLimits&limits=MeshLimits{}){
 if(!valid_region(x0,z0,size,limits)||field.size()!=size_t(size+1)*(size+1)*257){Result invalid;invalid.status=MeshStatus::invalid_input;return invalid;}
 size_t plane=size_t(size+1)*(size+1);
 return mesh_layers(x0,z0,size,retire_edges,[&](int y){return field.data()+size_t(y)*plane;},limits);
}

static float density_value(float d){
 float v=clampf(d,-SDF_BAND,SDF_BAND)*SDF_SCALE;int q=int(v>=0?v+.5f:v-.5f);
 return q?float(q)/SDF_SCALE:.5f/SDF_SCALE;
}


} // namespace terraforest::experimental
