// SPDX-License-Identifier: 0BSD
#pragma once
#include "world_region_sampler.hpp"

namespace terraforest::experimental {
// Geometry-only ownership experiment. Capture requires an immutable World for
// its duration. Afterwards no World or page pointer is retained. Custom allocator
// contexts must still outlive this object, as required by FallibleBuffer.
// This is not a material/normal/lighting snapshot or a runtime job interface.
class RegionSnapshot {
 FallibleBuffer<float> density_;
 int x_=0,z_=0,size_=0,revision_=-1;
 MeshStatus status_=MeshStatus::invalid_input;
public:
 MeshStatus status()const{return status_;}
 int revision()const{return revision_;}
 size_t bytes()const{return density_.size()*sizeof(float);}
 MeshStatus capture(const World&w,int x,int z,int size,const MeshLimits&limits=MeshLimits{}){
  density_.clear();revision_=-1;status_=MeshStatus::invalid_input;
  if(!valid_region(x,z,size,limits)||!w.edit_columns)return status_;
  WorldRegionSampler sampler(w,x,z,size,limits);
  status_=sampler.status;
  if(status_!=MeshStatus::ok)return status_;
  density_.set_allocator(limits.sampler_allocator);
  const size_t plane=size_t(size+1)*(size+1);
  if(!density_.resize(plane*(WORLD_Y+1))){status_=MeshStatus::allocation_failed;return status_;}
  for(int y=0;y<WORLD_Y;y++){
   const float*pair=sampler.layers(y);
   if(!pair){density_.clear();status_=sampler.status;return status_;}
   std::copy(pair,pair+plane,density_.data()+size_t(y)*plane);
   if(y==WORLD_Y-1)std::copy(pair+plane,pair+2*plane,density_.data()+size_t(y+1)*plane);
  }
  if(limits.cancelled()){density_.clear();status_=MeshStatus::cancelled;return status_;}
  x_=x;z_=z;size_=size;revision_=w.revision;
  return status_;
 }
 Result mesh(const MeshLimits&limits=MeshLimits{})const{
  if(status_!=MeshStatus::ok){Result r;r.status=status_;return r;}
  const size_t plane=size_t(size_+1)*(size_+1);
  return mesh_layers(x_,z_,size_,true,[&](int y){return density_.data()+size_t(y)*plane;},limits);
 }
};
}
