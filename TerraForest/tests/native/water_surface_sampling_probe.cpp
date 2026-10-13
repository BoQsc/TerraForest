// SPDX-License-Identifier: 0BSD
// Admission diagnostic for direct regular-grid reuse, not another runtime.
#include "../../addons/volumetric_terrain/native/core.h"
#include "../../addons/volumetric_terrain/native/surface_cell.hpp"
#include "../../addons/volumetric_water/native/water_surface_interval.hpp"
#include <cstdio>
#include <algorithm>
#include <cmath>
// Exact box sign: negative only inside the finite volume. Authoritative water
// is unchanged; this evaluates the proposed rendering adapter only.
float field(V3 p,float bottom,float depth){
 return std::max({-p.x,p.x-2.f,-p.z,p.z-2.f,bottom-p.y,p.y-bottom-depth});
}
int surface_cells(float bottom,float depth,float spacing){
 int count=0;
 for(int z=-1;z<5;z++)for(int y=-1;y<5;y++)for(int x=-1;x<5;x++){
  float d[8];unsigned mask=0;
  for(int k=0;k<8;k++){
   V3 p={spacing*(x+(k&1)),spacing*(y+((k>>1)&1)),spacing*(z+((k>>2)&1))};
   d[k]=field(p,bottom,depth);if(d[k]<0)mask|=1u<<k;
  }
  if(mask&&mask!=255){
   V3 p=terraforest::surface_cell_vertex<V3>(d,mask);
   if(!std::isfinite(p.x+p.y+p.z))return -1;
   count++;
  }
 }
 return count;
}
int main(){
 // 16 regular cells covering 2x2 m. 1000 ml per 0.25 m^2 = 4 mm.
 int lake=surface_cells(0.f,1.f,.5f);
 int missed=0,seen=0;
 for(int i=0;i<1000;i++){
  float bottom=i*.0005f;
  int count=surface_cells(bottom,.004f,.5f);
  if(count<0)return 1;
  if(count)seen++;else missed++;
 }
 std::printf("deep_pool_surface_cells=%d shallow_phases_visible=%d shallow_phases_missing=%d/1000\n",lake,seen,missed);
 if(lake<=0||missed==0)return 2;
 std::puts("DIRECT_UNIFORM_GRID_ADOPTION=REJECTED: finite stored water can have no surface samples");
 // Shared runtime/render connection rejects solid separation and dry ledges,
 // but retains exact 1 ml connections where two wet intervals really meet.
 using terraforest::water_intervals_joined;
 if(water_intervals_joined(0,200,50000,200,500,1000))return 8;
 if(water_intervals_joined(0,500,25000,100,500,1))return 9;
 if(!water_intervals_joined(0,500,25001,100,500,1))return 10;
 if(water_intervals_joined(0,0,1000,0,500,1000))return 11;
 if(water_intervals_joined(0,500,0,0,500,1000))return 12;
 int preserved=0;
 for(int y=2;y<509;y++)for(int floor=0;floor<500;floor+=7){
  auto interval=terraforest::WaterSurfaceInterval::from_cell(y,floor,500,1000);
  if(!interval.wet)return 3;
  double tops[4]={interval.top,interval.top,interval.top,interval.top};float density[8];
  int slab=interval.top_slab();unsigned signs=terraforest::water_sheet_samples(tops,slab,density);
  if(signs==0||signs==255)return 4;
  V3 representative=terraforest::surface_cell_vertex<V3>(density,signs);
  double reconstructed=slab*.5+representative.y*.5;
  if(std::abs(reconstructed-interval.top)>0.00000004)return 5;
  // Lower and upper surfaces remain independently representable in one cell.
  auto upper=terraforest::WaterSurfaceInterval::from_cell(y,499,500,250);
  if(upper.top-interval.top>1e-9){
   double upper_tops[4]={upper.top,upper.top,upper.top,upper.top};float upper_density[8];
   unsigned upper_signs=terraforest::water_sheet_samples(upper_tops,upper.top_slab(),upper_density);
   V3 upper_point=terraforest::surface_cell_vertex<V3>(upper_density,upper_signs);
   double upper_reconstructed=upper.top_slab()*.5+upper_point.y*.5;
   if(upper_reconstructed<=reconstructed||std::abs(upper_reconstructed-upper.top)>0.00000004)return 6;
  }
  preserved++;
 }
 auto dry=terraforest::WaterSurfaceInterval::from_cell(10,0,500,0);
 auto solid=terraforest::WaterSurfaceInterval::from_cell(10,500,500,1000);
 auto overflow=terraforest::WaterSurfaceInterval::from_cell(10,0,500,999999);
 if(dry.wet||solid.wet||overflow.top!=5.5)return 7;
 std::printf("EXPOSED_SHEET_HEIGHTS=PASS %d world-height/floor cases; dry, solid and capacity guards pass\n",preserved);
 std::puts("RUNTIME_ADOPTION=NOT_QUALIFIED: connectivity, shores and query agreement still required");
 return 0;
}
