// SPDX-License-Identifier: 0BSD
#include "../../addons/volumetric_water/native/water_cell_profile.hpp"
#include <cstdio>
#include <cstdlib>
using terraforest::WaterCellProfile;
static void require(bool ok,const char *name){std::printf("%s %s\n",ok?"PASS":"FAIL",name);if(!ok)std::exit(1);}
int main(){
    WaterCellProfile ramp;ramp.floor={0,500,0,500};
    require(ramp.capacity()==62500,"sloped half-cell capacity is 62.5 litres");
    require(std::abs(ramp.volume(250)-15625)<1e-6,"quarter-height wedge integrates to 15.625 litres");
    for(uint64_t ml:{1u,10u,1000u,10000u,62500u})require(std::abs(ramp.volume(ramp.head(ml))-ml)<0.02,"head inversion conserves sub-litre and full-cell quantities");
    auto shape=ramp.footprint(250);
    require(std::abs(shape.area-0.5)<1e-8&&std::abs(shape.x-0.25)<1e-8&&std::abs(shape.z-0.5)<1e-8,"wetted centroid excludes the dry half of the slope");
    require(ramp.opening(0,0)==0&&ramp.opening(0,1)==500,"opposite floor faces have distinct spill heights");
    WaterCellProfile flat;flat.floor.fill(275);
    require(flat.capacity()==56250&&flat.head(10000)==315,"flat cells retain their exact constant-area behavior");
    float wall[8]={-1,-1,-1,-1,1,1,1,1};
    auto closed=WaterCellProfile::make(wall,true,500,500);
    require(!closed.cut&&closed.capacity()==0,"ambiguous walls retain conservative closure");
    float slope[8]={0,-1,1,1,0,-1,1,1};
    auto cut=WaterCellProfile::make(slope,true,250,500);
    require(cut.cut&&cut.capacity()==93750&&!cut.open_bottom,"cached floor crossings recover partial capacity without opening solid bottom");
    float crossing_top[8]={-0.4f,-0.6f,0.1f,-0.1f,-0.4f,-0.6f,0.1f,-0.1f};
    auto partial=WaterCellProfile::make(crossing_top,true,500,500);
    require(partial.cut&&std::abs(double(partial.capacity())-6250)<2,"floor crossing the cell top retains its partial air wedge");
    std::puts("WATER_CELL_PROFILE failures=0");
}
