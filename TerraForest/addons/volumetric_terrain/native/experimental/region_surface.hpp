// SPDX-License-Identifier: 0BSD
#pragma once
#include "world_region_sampler.hpp"
#include "region_normals.hpp"

namespace terraforest::experimental {
// Worker-owned CPU surface. No engine resources, material packet or collision
// object yet. World storage must remain immutable throughout the synchronous call.
struct RegionSurface {
 Result geometry;
 NormalResult normals;
 MeshStatus status=MeshStatus::invalid_input;
 int x=0,z=0,size=0,revision=0;
 void discard(MeshStatus why){
  geometry.discard(why);normals.discard(why);status=why;
 }
 bool ready()const{
  return status==MeshStatus::ok&&geometry.status==MeshStatus::ok&&
      normals.status==MeshStatus::ok&&geometry.p.size()==normals.values.size();
 }
};

static RegionSurface build_world_surface(const World&w,int x,int z,int size,const MeshLimits&limits=MeshLimits{}){
 RegionSurface surface;surface.x=x;surface.z=z;surface.size=size;
 surface.geometry=build_world_region(w,x,z,size,limits);
 if(surface.geometry.status!=MeshStatus::ok){surface.discard(surface.geometry.status);return surface;}
 surface.normals=build_region_normals_cached(w,surface.geometry,x,z,size,limits,true);
 if(surface.normals.status!=MeshStatus::ok){surface.discard(surface.normals.status);return surface;}
 if(limits.cancelled()){surface.discard(MeshStatus::cancelled);return surface;}
 if(surface.geometry.p.size()!=surface.normals.values.size()){surface.discard(MeshStatus::internal_error);return surface;}
 surface.revision=w.revision;surface.status=MeshStatus::ok;
 return surface;
}
} // namespace terraforest::experimental
