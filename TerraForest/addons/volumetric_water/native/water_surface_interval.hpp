// SPDX-License-Identifier: 0BSD
#pragma once
#include <algorithm>
#include <cstdint>
#include <cmath>
namespace terraforest {
// Rendering adapter for an exposed finite-volume interface. Quantities remain
// authoritative; this does not thicken a puddle or invent negative volume below
// its floor. A sheet is a surface description, not a simulation density field.
struct WaterSurfaceInterval {
 double bottom=0,top=0;
 bool wet=false;
 static WaterSurfaceInterval from_cell(int y,uint16_t floor,uint16_t ceiling,uint64_t ml){
  WaterSurfaceInterval result;
  if(floor>=ceiling||ceiling>500||ml==0)return result;
  result.bottom=y*0.5+floor*0.001;
  result.top=result.bottom+double(std::min(ml,uint64_t(ceiling-floor)*250))/250000.0;
  result.wet=true;return result;
 }
 // Select a slab containing the top even if bottom and top are inside the
 // same original cell. Exact lattice tops belong to the slab below them.
 int top_slab()const{return int(std::ceil(top*2.0))-1;}
 double local_top(int slab)const{return (top-slab*0.5)*2.0;}
};
// Four X/Z column tops, ordered 00,10,01,11. Caller must first establish that
// they belong to the same exposed connected sheet. Never average stacked pools
// or cross a solid barrier here. These signed samples describe that sheet only.
inline unsigned water_sheet_samples(const double *tops,int slab,float *density){
 unsigned signs=0;
 for(int k=0;k<8;k++){
  int column=(k&1)+2*((k>>2)&1);
  density[k]=float(((k>>1)&1)-(tops[column]-slab*0.5)*2.0);
  if(density[k]<0)signs|=1u<<k;
 }
 return signs;
}
// Same-layer finite-volume connection, shared by rendering and bucket traversal.
// Amount comparisons stay integer-exact, including sub-millimetre water.
inline bool water_intervals_joined(uint16_t af,uint16_t ac,uint64_t av,
                                   uint16_t bf,uint16_t bc,uint64_t bv){
 const uint64_t opening=std::max(af,bf);
 return opening<std::min(ac,bc)&&uint64_t(af)*250+av>opening*250&&uint64_t(bf)*250+bv>opening*250;
}
}
