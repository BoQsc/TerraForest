// SPDX-License-Identifier: 0BSD
#pragma once
#include "biome_field.hpp"
#include "landform_shapes.hpp"
#include <vector>
#include <array>
#include <cstring>
namespace terraforest::landforms {
// Immutable v3 shore composition. Fixed guide records, no scene or file access.
// The wet outline/depth is unchanged; broad dry banks carry rolling shoulders.
template<class Noise> inline float habitat_dry_ground(float ground,float dry,float level,Noise noise){
 if(dry>=160.f)return ground;
 const float margin=shapes::smooth((noise(92,211)+.25f)*1.1f);
 const float transition=36.f+48.f*margin;
 const float reach=1-shapes::smooth(dry/160.f);
 const float shoulder=shapes::smooth(dry/24.f)*reach;
 // Broad shoulders and interleaved swales follow the bank, fading continuously
 // to the existing countryside; never make a raised retaining rim in the water.
 const float rolls=2.8f*(.55f+.45f*noise(79,887))+1.1f*noise(29,907);
 const float terrain=ground+shoulder*rolls;
 return level+(terrain-level)*shapes::smooth(dry/transition);
}
template<class Noise> inline float habitat_ground(float ground,float distance,float width,float bank,float level,float depth,float variation,Noise noise){
 const float cove=variation*(.72f*noise(58,173)+.28f*noise(19,197));
 const float dry=distance-width*(1+cove);
 return dry<=0?shapes::lake(ground,distance,width,bank,level,depth,variation,noise):habitat_dry_ground(ground,dry,level,noise);
}
template<class Noise> inline float habitat_woodland(float base,float dry,Noise noise){
 if(dry>=160.f)return base;
 const float weight=1-shapes::smooth(std::max(0.f,dry)/160.f);
 const float groves=shapes::smooth((noise(47,929)+.45f)/1.1f);
 const float meadow=shapes::smooth((noise(113,953)-.15f)/.65f);
 const float target=(.30f+.58f*groves)*(1-.75f*meadow);
 return base+(target-base)*weight;
}
struct ShoreSegment {float ax,az,aw,bx,bz,bw;};
class ShoreHabitat {
 std::vector<ShoreSegment> segments;
 std::array<std::vector<uint16_t>,1024> bins;
 uint32_t seed=0;
 static uint32_t u32(const uint8_t*p){return uint32_t(p[0])|uint32_t(p[1])<<8|uint32_t(p[2])<<16|uint32_t(p[3])<<24;}
 static float f32(const uint8_t*p){uint32_t n=u32(p);float f;std::memcpy(&f,&n,4);return f;}
public:
 static constexpr uint32_t MAGIC=0x31524853,MAX_SEGMENTS=384;
 bool decode(const uint8_t*p,size_t size){
  if(size<16||u32(p)!=MAGIC||u32(p+4)!=1||u32(p+8)>MAX_SEGMENTS||size!=16+size_t(u32(p+8))*24||u32(p+12)>2147483647)return false;
  std::vector<ShoreSegment> next;next.reserve(u32(p+8));
  for(uint32_t i=0;i<u32(p+8);i++){
   const auto*q=p+16+i*24;ShoreSegment s{f32(q),f32(q+4),f32(q+8),f32(q+12),f32(q+16),f32(q+20)};
   for(float v:{s.ax,s.az,s.aw,s.bx,s.bz,s.bw})if(!std::isfinite(v))return false;
   if(std::min({s.ax,s.az,s.bx,s.bz})<0||std::max({s.ax,s.az,s.bx,s.bz})>2000||std::min(s.aw,s.bw)<=0||std::max(s.aw,s.bw)>128||std::hypot(s.bx-s.ax,s.bz-s.az)<.0001f)return false;
   next.push_back(s);
  }
  segments.swap(next);seed=u32(p+12);for(auto&bin:bins)bin.clear();
  for(size_t i=0;i<segments.size();i++){
   const auto&s=segments[i];float r=std::max(s.aw,s.bw)*1.2f+160;
   int x0=std::clamp(int((std::min(s.ax,s.bx)-r)/64),0,31),x1=std::clamp(int((std::max(s.ax,s.bx)+r)/64),0,31);
   int z0=std::clamp(int((std::min(s.az,s.bz)-r)/64),0,31),z1=std::clamp(int((std::max(s.az,s.bz)+r)/64),0,31);
   for(int z=z0;z<=z1;z++)for(int x=x0;x<=x1;x++)bins[x+32*z].push_back(uint16_t(i));
  }return true;
 }
 float woodland(float x,float z,float base)const{
  if(x<0||z<0||x>=2000||z>=2000)return base;
  float dry=1e20f;
  auto noise=[&](float scale,uint32_t salt){return float(biome_noise(x/scale,z/scale,seed^salt))*2-1;};
  for(uint16_t i:bins[int(x/64)+32*int(z/64)]){
   const auto&s=segments[i];float dx=s.bx-s.ax,dz=s.bz-s.az;
   float t=std::clamp(((x-s.ax)*dx+(z-s.az)*dz)/(dx*dx+dz*dz),0.f,1.f);
   float width=s.aw+(s.bw-s.aw)*t;dx=x-s.ax-t*dx;dz=z-s.az-t*dz;
   dry=std::min(dry,std::sqrt(dx*dx+dz*dz)-width);
  }
  return habitat_woodland(base,dry,noise);
 }
};
}
