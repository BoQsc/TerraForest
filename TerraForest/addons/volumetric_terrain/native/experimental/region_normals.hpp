// SPDX-License-Identifier: 0BSD
#pragma once
#include "region_mesher.hpp"

namespace terraforest::experimental {
struct NormalResult {
 FallibleBuffer<V3> values;
 MeshStatus status=MeshStatus::ok;
 size_t samples=0;
 size_t density_evaluations=0,scratch_bytes=0;
 void discard(MeshStatus why){values.clear();status=why;}
};
// Reference shading candidate: canonical world-space trilinear field gradient.
// No owner-relative clamping or triangle adjacency, so shared positions use the
// same samples. Not a geometric normal of the tetrahedral interpolant.
template<class SampleDensity>
static NormalResult build_normals_from_samples(const Result&mesh,const MeshLimits&limits,SampleDensity&&sample){
 NormalResult out;
 if(mesh.status!=MeshStatus::ok||!limits.output_allocator.allocate||!limits.output_allocator.release){out.status=MeshStatus::invalid_input;return out;}
 if(limits.cancelled()){out.status=MeshStatus::cancelled;return out;}
 if(mesh.p.size()>limits.vertices){out.status=MeshStatus::output_limit;return out;}
 out.values.set_allocator(limits.output_allocator);
 if(!out.values.resize(mesh.p.size())){out.status=MeshStatus::allocation_failed;return out;}
 for(size_t i=0;i<mesh.p.size();i++){
  if((i&31)==0&&limits.cancelled()){out.discard(MeshStatus::cancelled);return out;}
  V3 p=mesh.p[i];
  if(!std::isfinite(p.x)||!std::isfinite(p.y)||!std::isfinite(p.z)||p.x<0||p.x>WORLD||p.z<0||p.z>WORLD||p.y<0||p.y>256){out.discard(MeshStatus::invalid_input);return out;}
  int x=fl(p.x),y=fl(p.y),z=fl(p.z);V3 f{p.x-x,p.y-y,p.z-z},g{};
  for(int k=0;k<8;k++){
   float raw=sample(x+(k&1),y+((k>>1)&1),z+((k>>2)&1));out.samples++;
   if(!std::isfinite(raw)){out.discard(MeshStatus::invalid_input);return out;}
   float d=density_value(raw);
   float wx=k&1?f.x:1-f.x,wy=k&2?f.y:1-f.y,wz=k&4?f.z:1-f.z;
   g.x+=d*(k&1?1.f:-1.f)*wy*wz;
   g.y+=d*(k&2?1.f:-1.f)*wx*wz;
   g.z+=d*(k&4?1.f:-1.f)*wx*wy;
  }
  float magnitude=length(g);
  if(!std::isfinite(magnitude)||magnitude<1e-8f){out.discard(MeshStatus::invalid_input);return out;}
  out.values[i]=g/magnitude;
 }
 if(limits.cancelled())out.discard(MeshStatus::cancelled);
 return out;
}
static NormalResult build_region_normals(const World&w,const Result&mesh,const MeshLimits&limits=MeshLimits{}){
 if(!w.edit_columns){NormalResult failed;failed.status=MeshStatus::invalid_input;return failed;}
 return build_normals_from_samples(mesh,limits,[&](int x,int y,int z){return w.sample(x,y,z);});
}
// Retain one height per horizontal lattice column, including the positive halo
// read by canonical cells on the region boundary. No persistent world cache.
static NormalResult build_region_normals_cached(const World&w,const Result&mesh,int x0,int z0,int size,const MeshLimits&limits=MeshLimits{},bool reuse_density=false){
 NormalResult failed;
 if(!valid_region(x0,z0,size,limits)||!w.edit_columns||mesh.status!=MeshStatus::ok){failed.status=MeshStatus::invalid_input;return failed;}
 if(limits.cancelled()){failed.status=MeshStatus::cancelled;return failed;}
 if(mesh.p.size()>limits.vertices){failed.status=MeshStatus::output_limit;return failed;}
 for(V3 p:mesh.p)if(!std::isfinite(p.x)||!std::isfinite(p.z)||p.x<x0||p.x>x0+size||p.z<z0||p.z>z0+size){failed.status=MeshStatus::invalid_input;return failed;}
 int n=size+2;FallibleBuffer<float> heights;heights.set_allocator(limits.sampler_allocator);
 if(!heights.resize(size_t(n)*n)){failed.status=MeshStatus::allocation_failed;return failed;}
 // Tags make reuse correct even if input vertices are not ordered by height.
 // Colliding layers evict entries, never return a different layer's density.
 struct Entry{float value=0;int y=-1;};FallibleBuffer<Entry> density;
 density.set_allocator(limits.sampler_allocator);
 if(reuse_density&&!density.resize(size_t(3)*n*n)){failed.status=MeshStatus::allocation_failed;return failed;}
 for(int z=0;z<n;z++){
  if(limits.cancelled()){failed.status=MeshStatus::cancelled;return failed;}
  for(int x=0;x<n;x++)heights[x+n*z]=w.height(float(x0+x),float(z0+z));
 }
 size_t evaluations=0;
 auto evaluate=[&](int x,int y,int z){
  evaluations++;
  if(x<0||x>WORLD||z<0||z>WORLD||y<0||y>WORLD_Y)return SDF_BAND;
  constexpr int np=WORLD/PAGE+1;
  int page=w.pages_by_key.get(u32((x>>4)+np*((z>>4)+np*(y>>4)))+1);
  if(page>=0)return float(w.pages[page].d[(x&15)+16*((z&15)+16*(y&15))])/SDF_SCALE;
  return w.base({float(x),float(y),float(z)},heights[(x-x0)+n*(z-z0)]);
 };
 NormalResult result=build_normals_from_samples(mesh,limits,[&](int x,int y,int z){
  if(!reuse_density)return evaluate(x,y,z);
  Entry&entry=density[size_t(y%3)*n*n+(z-z0)*n+(x-x0)];
  if(entry.y!=y){entry.value=evaluate(x,y,z);entry.y=y;}
  return entry.value;
 });
 result.density_evaluations=evaluations;
 result.scratch_bytes=heights.size()*sizeof(float)+density.size()*sizeof(Entry);
 return result;
}
} // namespace terraforest::experimental
