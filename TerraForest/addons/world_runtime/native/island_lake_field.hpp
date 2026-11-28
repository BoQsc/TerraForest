// SPDX-License-Identifier: 0BSD
#pragma once
#include "island_lake_modules.hpp"
#include "shore_habitat.hpp"
#include <cstdint>
namespace terraforest::landforms {
// Derived fixed records and one-dimensional broad phase. Rebuilt once from seed
// and immutable constants; not a second serialized terrain authority.
struct IslandLakeField {
 GuideSegment segments[128]{};
 uint8_t bins[16][128]{},counts[16]{};
 struct Group{float x0,z0,x1,z1,width;unsigned first,last;};
 Group groups[16]{};unsigned group_count=0;
 unsigned count=0;float length=1,bank=24;
 void init(unsigned kind,float half_length,float half_width,uint32_t seed,bool habitat=false){
  const auto&guide=island_guides[kind%3];count=guide.count;length=half_length;
  bank=habitat?160.f:std::min(24.f,half_width*.6f);
  for(auto &n:counts)n=0;
  const float flip=(seed&1)?-1.f:1.f;
  for(unsigned i=0;i<count;i++){
   const auto&s=guide.segments[i];auto&d=segments[i];
   d={s.ax*length,s.az*half_width*flip,s.aw*half_width,s.bx*length,s.bz*half_width*flip,s.bw*half_width};
   float reach=std::max(d.aw,d.bw)*1.2f+bank;
   int lo=std::clamp(int(((std::min(d.ax,d.bx)-reach)/length+1)*8),0,15),hi=std::clamp(int(((std::max(d.ax,d.bx)+reach)/length+1)*8),0,15);
   for(int b=lo;b<=hi;b++)bins[b][counts[b]++]=uint8_t(i);
  }
  group_count=0;
  if(habitat)for(unsigned first=0;first<count;first+=8){
   Group g{1e20f,1e20f,-1e20f,-1e20f,0,first,std::min(first+8,count)};
   for(unsigned i=g.first;i<g.last;i++){const auto&s=segments[i];g.x0=std::min({g.x0,s.ax,s.bx});g.z0=std::min({g.z0,s.az,s.bz});g.x1=std::max({g.x1,s.ax,s.bx});g.z1=std::max({g.z1,s.az,s.bz});g.width=std::max({g.width,s.aw,s.bw});}
   groups[group_count++]=g;
  }
 }
 template<class Noise> float height(float x,float z,float ground,float level,float depth,Noise noise,bool habitat=false)const{
  int bin=std::clamp(int((x/length+1)*8),0,15);float best=1e20f,distance=0,width=1,edge=1e20f;
  const float wet_scale=habitat?1+.18f*(.72f*noise(58,173)+.28f*noise(19,197)):1.f;
  unsigned best_index=128;
  auto visit=[&](unsigned index){
   const auto&s=segments[index];float dx=s.bx-s.ax,dz=s.bz-s.az;
   float t=std::clamp(((x-s.ax)*dx+(z-s.az)*dz)/(dx*dx+dz*dz),0.f,1.f);
   float w=s.aw+(s.bw-s.aw)*t;dx=x-s.ax-t*dx;dz=z-s.az-t*dz;
   float d2=dx*dx+dz*dz,q=d2/(w*w);if(q<best||(habitat&&q==best&&index<best_index)){best=q;distance=d2;width=w;best_index=index;}
   if(habitat){
    // Reject noncompetitive segments with squared distances before sqrt.
    float radius=edge+w*wet_scale;
    if(radius>0&&d2<radius*radius)edge=std::sqrt(d2)-w*wet_scale;
   }
  };
  if(!habitat){for(unsigned n=0;n<counts[bin];n++)visit(bins[bin][n]);}
  else{
   // Bounded, allocation-free branch-and-bound over compiled curve groups.
   // The lower bounds preserve both the wet radius and dry edge minimum.
   struct Candidate{float edge,q;unsigned index;};Candidate order[16];unsigned used=0;
   for(unsigned i=0;i<group_count;i++){
    const auto&g=groups[i];float dx=std::max({g.x0-x,x-g.x1,0.f}),dz=std::max({g.z0-z,z-g.z1,0.f}),d2=dx*dx+dz*dz;
    Candidate c{std::sqrt(d2)-g.width*wet_scale,d2/(g.width*g.width),i};unsigned at=used++;
    while(at&&order[at-1].edge>c.edge){order[at]=order[at-1];--at;}order[at]=c;
   }
   for(unsigned at=0;at<used;at++){
    const auto&c=order[at];const float needed_q=edge>0?wet_scale*wet_scale:best;
    if(c.edge>edge+.001f&&c.q>needed_q+.000001f)continue;
    const auto&g=groups[c.index];for(unsigned i=g.first;i<g.last;i++)visit(i);
   }
  }
  if(best==1e20f)return ground;
  if(!habitat&&distance>(width*1.2f+bank)*(width*1.2f+bank))return ground;
  // Wet depth uses the frozen normalized-radius field. Dry shoulders use the
  // minimum signed distance to the actual bank: unlike carrying the winning
  // segment's width across its Voronoi boundary, that minimum is continuous.
  if(habitat&&edge>0)return habitat_dry_ground(ground,edge,level,noise);
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
