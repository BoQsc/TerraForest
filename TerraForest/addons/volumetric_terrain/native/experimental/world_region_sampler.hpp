// SPDX-License-Identifier: 0BSD
#pragma once
#include "region_mesher.hpp"

namespace terraforest::experimental {
// Internal sequential sampler. Border-crossing extents are permitted here for
// sampling controls; the public meshing entry point requires an in-world region.
struct WorldRegionSampler {
 const World&w;int x0,z0,n=0,page_y=-1,next_layer=0;
 size_t plane=0;
 std::vector<float> planes,heights;
 std::vector<int> page_indices;
 MeshLimits limits;MeshStatus status=MeshStatus::ok;
 bool checkpoint(){
  if(status!=MeshStatus::ok)return false;
  if(limits.cancelled()){status=MeshStatus::cancelled;return false;}
  return true;
 }
 WorldRegionSampler(const World&world,int x,int z,int size,const MeshLimits&control=MeshLimits{}):w(world),x0(x),z0(z),limits(control){
  if(size<1||size>32||x<-32||z<-32||x>WORLD||z>WORLD||!w.edit_columns){status=MeshStatus::invalid_input;return;}
  if(!checkpoint())return;
  n=size+1;plane=size_t(n)*n;
  planes.resize(plane*2);heights.resize(plane);page_indices.resize(plane);
  for(int dz=0;dz<n;dz++){
   if(!checkpoint())return;
   for(int dx=0;dx<n;dx++)heights[dx+n*dz]=w.height(float(x0+dx),float(z0+dz));
  }
  fill(0,planes.data());fill(1,planes.data()+plane);
 }
 void fill(int y,float*out){
  if(status!=MeshStatus::ok)return;
  constexpr int np=WORLD/PAGE+1;
  int py=y>>4;
  if(py!=page_y){
   for(int z=0;z<n;z++){
    if(!checkpoint())return;
    for(int x=0;x<n;x++){
     int wx=x0+x,wz=z0+z;
     page_indices[x+n*z]=(wx<0||wx>WORLD||wz<0||wz>WORLD)?-2:w.pages_by_key.get(u32((wx>>4)+np*((wz>>4)+np*py))+1);
    }
   }
   page_y=py;
  }
  for(int z=0;z<n;z++){
   if(!checkpoint())return;
   for(int x=0;x<n;x++){
    int wx=x0+x,wz=z0+z,at=x+n*z,pi=page_indices[at];
    float d=pi==-2?SDF_BAND:(pi<0?w.base({float(wx),float(y),float(wz)},heights[at]):float(w.pages[pi].d[(wx&15)+16*((wz&15)+16*(y&15))])/SDF_SCALE);
    out[at]=density_value(d);
   }
  }
 }
 const float*layers(int y){
  if(status!=MeshStatus::ok)return nullptr;
  if(y!=next_layer||y<0||y>=256){status=MeshStatus::invalid_input;return nullptr;}
  if(!checkpoint())return nullptr;
  if(y){std::copy(planes.begin()+plane,planes.end(),planes.begin());fill(y+1,planes.data()+plane);}
  if(status!=MeshStatus::ok)return nullptr;
  next_layer++;
  return planes.data();
 }
 size_t payload_bytes()const{return (planes.size()+heights.size())*sizeof(float)+page_indices.size()*sizeof(int);}
};

static Result build_world_region(const World&w,int x,int z,int size,const MeshLimits&limits=MeshLimits{}){
 Result result;
 if(!valid_region(x,z,size,limits)||!w.edit_columns){result.status=MeshStatus::invalid_input;return result;}
 if(limits.cancelled()){result.status=MeshStatus::cancelled;return result;}
 WorldRegionSampler sampler(w,x,z,size,limits);
 if(sampler.status!=MeshStatus::ok){result.status=sampler.status;return result;}
 result=mesh_layers(x,z,size,true,[&](int y){return sampler.layers(y);},limits);
 // A cancelled provider returns nullptr. Preserve its cancellation status rather
 // than reporting malformed input, and never return its incomplete geometry.
 if(sampler.status!=MeshStatus::ok)result.discard(sampler.status);
 return result;
}
} // namespace terraforest::experimental
