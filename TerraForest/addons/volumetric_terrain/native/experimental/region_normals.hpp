// SPDX-License-Identifier: 0BSD
#pragma once
#include "region_mesher.hpp"

namespace terraforest::experimental {
struct NormalResult {
 FallibleBuffer<V3> values;
 MeshStatus status=MeshStatus::ok;
 size_t samples=0;
 void discard(MeshStatus why){values.clear();status=why;}
};
// Reference shading candidate: canonical world-space trilinear field gradient.
// No owner-relative clamping or triangle adjacency, so shared positions use the
// same samples. Not a geometric normal of the tetrahedral interpolant.
static NormalResult build_region_normals(const World&w,const Result&mesh,const MeshLimits&limits=MeshLimits{}){
 NormalResult out;
 if(!w.edit_columns||mesh.status!=MeshStatus::ok||!limits.output_allocator.allocate||!limits.output_allocator.release){out.status=MeshStatus::invalid_input;return out;}
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
   float d=density_value(w.sample(x+(k&1),y+((k>>1)&1),z+((k>>2)&1)));out.samples++;
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
} // namespace terraforest::experimental
