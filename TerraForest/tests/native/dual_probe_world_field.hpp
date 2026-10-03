// SPDX-License-Identifier: 0BSD
#pragma once
#include "core.h"
#include "incremental_dual_probe.hpp"
namespace dual_probe {
static double canonical(float density){float v=std::max(-4.f,std::min(4.f,density))*1024.f;int q=int(v>=0?v+.5f:v-.5f);return q?double(q)/1024:.5/1024;}
struct WorldField{
 const World*world;P origin;mutable std::unordered_map<uint64_t,float> heights;
 double lattice(int x,int y,int z)const{
  if(x<0||x>WORLD||z<0||z>WORLD||y<0||y>WORLD_Y)return SDF_BAND;
  constexpr int np=WORLD/PAGE+1;int page=world->pages_by_key.get(uint32_t((x>>4)+np*((z>>4)+np*(y>>4)))+1);
  if(page>=0)return canonical(float(world->pages[page].d[(x&15)+16*((z&15)+16*(y&15))])/SDF_SCALE);
  uint64_t key=(uint64_t(uint32_t(x))<<32)|uint32_t(z);auto found=heights.find(key);float height;
  if(found==heights.end()){height=world->height(float(x),float(z));heights.emplace(key,height);}else height=found->second;
  return canonical(world->base({float(x),float(y),float(z)},height));
 }
 double operator()(P p)const{
  for(int k=0;k<3;k++)p[k]+=origin[k];int x=int(std::floor(p[0])),y=int(std::floor(p[1])),z=int(std::floor(p[2]));if(p[0]==x&&p[1]==y&&p[2]==z)return lattice(x,y,z);
  double d=0;for(int k=0;k<8;k++){int dx=k&1,dy=(k>>1)&1,dz=(k>>2)&1;d+=(dx?p[0]-x:1-(p[0]-x))*(dy?p[1]-y:1-(p[1]-y))*(dz?p[2]-z:1-(p[2]-z))*lattice(x+dx,y+dy,z+dz);}return d;
 }
};
} // namespace dual_probe
