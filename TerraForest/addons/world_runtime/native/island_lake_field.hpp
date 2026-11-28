// SPDX-License-Identifier: 0BSD
#pragma once
#include "island_lake_modules.hpp"
#include "landform_shapes.hpp"
#include <cstdint>
namespace terraforest::landforms {
// Derived fixed records and one-dimensional broad phase. Rebuilt once from seed
// and immutable constants; not a second serialized terrain authority.
struct IslandLakeField {
 GuideSegment segments[128]{};
 uint8_t bins[16][128]{},counts[16]{};
 unsigned count=0;float length=1,bank=24;
 void init(unsigned kind,float half_length,float half_width,uint32_t seed){
  const auto&guide=island_guides[kind%3];count=guide.count;length=half_length;
  bank=std::min(24.f,half_width*.6f);
  const float flip=(seed&1)?-1.f:1.f;
  for(unsigned i=0;i<count;i++){
   const auto&s=guide.segments[i];auto&d=segments[i];
   d={s.ax*length,s.az*half_width*flip,s.aw*half_width,s.bx*length,s.bz*half_width*flip,s.bw*half_width};
   float reach=std::max(d.aw,d.bw)*1.2f+bank;
   int lo=std::clamp(int(((std::min(d.ax,d.bx)-reach)/length+1)*8),0,15),hi=std::clamp(int(((std::max(d.ax,d.bx)+reach)/length+1)*8),0,15);
   for(int b=lo;b<=hi;b++)bins[b][counts[b]++]=uint8_t(i);
  }
 }
 template<class Noise> float height(float x,float z,float ground,float level,float depth,Noise noise)const{
  int bin=std::clamp(int((x/length+1)*8),0,15);float best=1e20f,distance=0,width=1;
  for(unsigned n=0;n<counts[bin];n++){
   const auto&s=segments[bins[bin][n]];float dx=s.bx-s.ax,dz=s.bz-s.az;
   float t=std::clamp(((x-s.ax)*dx+(z-s.az)*dz)/(dx*dx+dz*dz),0.f,1.f);
   float w=s.aw+(s.bw-s.aw)*t;dx=x-s.ax-t*dx;dz=z-s.az-t*dz;
   float d2=dx*dx+dz*dz,q=d2/(w*w);if(q<best){best=q;distance=d2;width=w;}
  }
  if(best==1e20f||distance>(width*1.2f+bank)*(width*1.2f+bank))return ground;
  return shapes::lake(ground,std::sqrt(distance),width,bank,level,depth,.18f,noise);
 }
 // A wet centerline point inside each adjacent physical-water catalog slice.
 bool source(float start,float end,float &x,float &z)const{
  float best=1e20f;bool found=false;const float middle=(start+end)*.5f;
  for(unsigned i=0;i<count;i++){
   const auto&s=segments[i];float dx=s.bx-s.ax;
   float t=std::abs(dx)>.001f?std::clamp((middle-s.ax)/dx,0.f,1.f):.5f;
   float px=s.ax+dx*t,pz=s.az+(s.bz-s.az)*t;
   if(px<=start+1||px>=end-1)continue;
   float cost=std::abs(px-middle);if(cost<best){best=cost;x=px;z=pz;found=true;}
  }return found;
 }
};
}
