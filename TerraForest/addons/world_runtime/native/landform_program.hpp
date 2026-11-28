// SPDX-License-Identifier: 0BSD
#pragma once
// Original authorable landform kernel. No Godot, GPU, file or scene dependencies.
// Compile guide curves once; sampling uses fixed records and spatial bins.
#include "biome_field.hpp"
#include "landform_shapes.hpp"
#include <array>
#include <vector>
#include <limits>
#include <cstring>
namespace terraforest::landforms {
constexpr uint32_t MAGIC=0x3150464c, VERSION=2, MAX_SEGMENTS=512, MAX_FEATURES=32;
enum Kind:uint32_t { COAST, RIDGE, LAKE, ISLAND, WOODLAND, CLEARING };
struct Point {float x=0,z=0,w=1;};
struct Segment {uint32_t kind=0,id=0;Point a,b;float level=0,depth=0,bank=0,variation=0;};
inline float smooth(float a){a=std::clamp(a,0.f,1.f);return a*a*(3-2*a);}
inline uint32_t u32(const uint8_t *p){return uint32_t(p[0])|uint32_t(p[1])<<8|uint32_t(p[2])<<16|uint32_t(p[3])<<24;}
inline void put32(uint8_t *p,uint32_t v){for(int i=0;i<4;i++)p[i]=uint8_t(v>>(8*i));}
inline float f32(const uint8_t *p){uint32_t v=u32(p);float f;std::memcpy(&f,&v,4);return f;}
inline void putf(uint8_t *p,float f){uint32_t v;std::memcpy(&v,&f,4);put32(p,v);}
inline uint64_t checksum(const uint8_t *p,size_t n){uint64_t h=14695981039346656037ull;for(size_t i=0;i<n;i++){h^=p[i];h*=1099511628211ull;}return h;}
struct Sample {float height=0,water=0,trees=0,grass=0;};
struct Program {
 uint32_t seed=0,version=VERSION;float extent=768,base=64,sea=40;
 std::vector<Segment> segments;
 std::array<std::vector<uint16_t>,256> bins;
 std::vector<uint16_t> coast;
 bool valid()const{
  if(seed>0x7fffffffu||!std::isfinite(extent)||extent<256||extent>2000||!std::isfinite(base)||base<45||base>150||!std::isfinite(sea)||sea<1||sea>base-4||segments.empty()||segments.size()>MAX_SEGMENTS)return false;
  std::array<const Segment*,MAX_FEATURES> groups{};
  for(const auto&s:segments){
   if(s.kind>CLEARING||s.id>=MAX_FEATURES)return false;
   for(float f:{s.a.x,s.a.z,s.a.w,s.b.x,s.b.z,s.b.w,s.level,s.depth,s.bank,s.variation})if(!std::isfinite(f))return false;
   if(s.a.x<0||s.a.z<0||s.b.x<0||s.b.z<0||s.a.x>extent||s.b.x>extent||s.a.z>extent||s.b.z>extent||s.a.w<2||s.b.w<2||s.a.w>256||s.b.w>256||s.bank<4||s.bank>128||s.depth<0||s.depth>100||s.level<sea||s.level>base+100||s.variation<0||s.variation>.2f)return false;
   const float dx=s.a.x-s.b.x,dz=s.a.z-s.b.z;if(dx*dx+dz*dz<.0001f)return false;
   if(groups[s.id]){const auto&t=*groups[s.id];if(s.kind!=t.kind||s.level!=t.level||s.depth!=t.depth||s.bank!=t.bank||s.variation!=t.variation)return false;}
   else groups[s.id]=&s;
  }
  // One closed coast chain, or an inland patch without a coast. Reject open rims.
  const Segment*first=nullptr,*last=nullptr;size_t count=0;
  for(const auto&s:segments)if(s.kind==COAST){if(!first)first=&s;if(last&&(last->b.x!=s.a.x||last->b.z!=s.a.z||last->id!=s.id))return false;last=&s;++count;}
  return !first||(count>=4&&last->b.x==first->a.x&&last->b.z==first->a.z);
 }
 void index(){
  coast.clear();for(auto&b:bins)b.clear();
  for(size_t i=0;i<segments.size();i++){
   const auto&s=segments[i];if(s.kind==COAST){coast.push_back(uint16_t(i));continue;}
   float reach=std::max(s.a.w,s.b.w)*1.2f+s.bank;
   int x0=std::clamp(int((std::min(s.a.x,s.b.x)-reach)*16/extent),0,15),x1=std::clamp(int((std::max(s.a.x,s.b.x)+reach)*16/extent),0,15);
   int z0=std::clamp(int((std::min(s.a.z,s.b.z)-reach)*16/extent),0,15),z1=std::clamp(int((std::max(s.a.z,s.b.z)+reach)*16/extent),0,15);
   for(int z=z0;z<=z1;z++)for(int x=x0;x<=x1;x++)bins[x+z*16].push_back(uint16_t(i));
  }
 }
 static float distance(float x,float z,const Segment&s,float &width){
  float dx=s.b.x-s.a.x,dz=s.b.z-s.a.z,t=std::clamp(((x-s.a.x)*dx+(z-s.a.z)*dz)/(dx*dx+dz*dz),0.f,1.f);
  width=s.a.w+(s.b.w-s.a.w)*t;dx=x-s.a.x-t*dx;dz=z-s.a.z-t*dz;return std::sqrt(dx*dx+dz*dz);
 }
 Sample sample(float x,float z)const{
  auto noise=[&](float scale,uint32_t salt){return float(biome_noise(x/scale,z/scale,seed^salt))*2-1;};
  Sample out;out.height=base+noise(210,31)*3+noise(65,47)*1.2f+noise(18,63)*.25f;
  std::array<float,MAX_FEATURES> radii; radii.fill(1e20f);
  std::array<float,MAX_FEATURES> distances{},widths{};std::array<const Segment*,MAX_FEATURES> nearest{};uint32_t active=0;
  const auto&near=bins[std::clamp(int(x*16/extent),0,15)+16*std::clamp(int(z*16/extent),0,15)];
  for(auto i:near){const auto&s=segments[i];float w;float d=distance(x,z,s,w);float q=d/w;if(q<radii[s.id]){radii[s.id]=q;distances[s.id]=d;widths[s.id]=w;nearest[s.id]=&s;active|=uint32_t(1)<<s.id;}}
  auto each=[&](auto fn){uint32_t mask=active;while(mask){int i=__builtin_ctz(mask);mask&=mask-1;fn(i,*nearest[i]);}};
  each([&](int i,const Segment&s){if(s.kind==RIDGE)out.height+=version==1?s.depth*smooth(1-radii[i]*radii[i])*(1+s.variation*noise(39,351+s.id)):shapes::ridge(radii[i],s.depth,s.variation,[&](float scale,uint32_t salt){return noise(scale,salt+s.id);});});
  float lake_level=0,shore_distance=10000;
  each([&](int i,const Segment&s){if(s.kind!=LAKE)return;
   if(version>=2){
    out.height=shapes::lake(out.height,distances[i],widths[i],s.bank,s.level,s.depth,s.variation,[&](float scale,uint32_t salt){return noise(scale,salt+s.id);});
    if(radii[i]<1.2f)lake_level=std::max(lake_level,s.level);
    shore_distance=std::min(shore_distance,std::abs(distances[i]-widths[i]));return;
   }
   float irregular=1+s.variation*noise(32,173+s.id),d=distances[i],w=widths[i]*irregular,q=d/w;
   if(d>w+s.bank)return;
   float target=q<1?s.level-s.depth+(s.depth+1.5f)*q*q:s.level+1.5f;
   float blend=1-smooth((d-w)/s.bank);out.height=out.height*(1-blend)+target*blend;
   if(q<1.15f)lake_level=std::max(lake_level,s.level);
   shore_distance=std::min(shore_distance,std::abs(d-w*.9f));
  });
  each([&](int i,const Segment&s){if(s.kind==ISLAND){float weight=smooth(1-radii[i]);out.height=std::max(out.height,(s.level+s.depth)*weight+out.height*(1-weight));}});
  float shore=10000;
  if(!coast.empty()){
   bool inside=false;float edge=1e20f;
   for(auto i:coast){const auto&s=segments[i];float unused;edge=std::min(edge,distance(x,z,s,unused));
    if((s.a.z>z)!=(s.b.z>z)&&x<(s.b.x-s.a.x)*(z-s.a.z)/(s.b.z-s.a.z)+s.a.x)inside=!inside;
   }
   shore=(inside?1.f:-1.f)*edge;float blend=smooth((shore+45)/120);
   out.height=version==1?(sea-12)*(1-blend)+out.height*blend:shapes::coast(out.height,shore,segments[coast[0]].bank,noise,sea);if(shore<25)out.water=sea;
  }
  out.water=std::max(out.water,lake_level);if(out.height>=out.water)out.water=0;
  out.trees=.08f+.42f*smooth((noise(130,129)+.2f)*1.2f);
  each([&](int i,const Segment&s){float weight=1-smooth((distances[i]-widths[i]) / s.bank);if(s.kind==WOODLAND)out.trees=std::max(out.trees,weight*.9f);if(s.kind==CLEARING)out.trees*=1-weight;});
  out.grass=.78f+.18f*noise(28,291);out.grass*=.85f+.15f*std::min(shore_distance/30,1.f);
  if(out.water||shore<12){out.trees=0;out.grass=0;}else out.trees*=smooth((shore-12)/24);
  return out;
 }
 std::vector<uint8_t> encode()const{
  if((version!=1&&version!=VERSION)||!valid())return {};std::vector<uint8_t>b(40+segments.size()*48,0);auto*p=b.data();put32(p,MAGIC);put32(p+4,version);put32(p+8,seed);putf(p+12,extent);putf(p+16,base);putf(p+20,sea);put32(p+24,uint32_t(segments.size()));
  for(size_t i=0;i<segments.size();i++){const auto&s=segments[i];auto*q=p+32+i*48;put32(q,s.kind);put32(q+4,s.id);float f[]={s.a.x,s.a.z,s.b.x,s.b.z,s.a.w,s.b.w,s.level,s.depth,s.bank,s.variation};for(int j=0;j<10;j++)putf(q+8+j*4,f[j]);}
  uint64_t sum=checksum(p,b.size()-8);put32(p+b.size()-8,uint32_t(sum));put32(p+b.size()-4,uint32_t(sum>>32));return b;
 }
 bool decode(const uint8_t*p,size_t n){
  if(n<40||n>40+MAX_SEGMENTS*48||u32(p)!=MAGIC||(u32(p+4)!=1&&u32(p+4)!=VERSION)||u32(p+28)!=0||u32(p+24)>MAX_SEGMENTS||n!=40+u32(p+24)*48)return false;
  if(checksum(p,n-8)!=(uint64_t(u32(p+n-8))|uint64_t(u32(p+n-4))<<32))return false;
  Program next;next.version=u32(p+4);next.seed=u32(p+8);next.extent=f32(p+12);next.base=f32(p+16);next.sea=f32(p+20);
  for(size_t i=0;i<u32(p+24);i++){const auto*q=p+32+i*48;next.segments.push_back({u32(q),u32(q+4),{f32(q+8),f32(q+12),f32(q+24)},{f32(q+16),f32(q+20),f32(q+28)},f32(q+32),f32(q+36),f32(q+40),f32(q+44)});}
  if(!next.valid())return false;next.index();*this=std::move(next);return true;
 }
};
inline Point curve(Point a,Point b,Point c,Point d,float t){
 auto value=[&](float a,float b,float c,float d){return .5f*((2*b)+(-a+c)*t+(2*a-5*b+4*c-d)*t*t+(-a+3*b-3*c+d)*t*t*t);};
 return {value(a.x,b.x,c.x,d.x),value(a.z,b.z,c.z,d.z),std::max(2.f,value(a.w,b.w,c.w,d.w))};
}
}
