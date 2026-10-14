// SPDX-License-Identifier: 0BSD
#include "../../addons/volumetric_water/native/water_solid_clip.hpp"
#include "../../addons/volumetric_water/native/water_cell_profile.hpp"
#include <cstdio>
#include <limits>
using C=terraforest::WaterSolidClip;
int failures=0;
void check(bool ok,const char*name){std::printf("%s %s\n",ok?"PASS":"FAIL",name);failures+=!ok;}
bool near(double a,double b){return std::abs(a-b)<1e-9;}
std::vector<C::Plane> box(C::Point a,C::Point b){return {{{-1,0,0},-a.x},{{1,0,0},b.x},{{0,-1,0},-a.y},{{0,1,0},b.y},{{0,0,-1},-a.z},{{0,0,1},b.z}};}
int main(){
 C::Pieces cell{C::box({0,0,0},{1,1,1})},air,next;
 check(near(C::volume(cell),1),"Unit volume");
 check(C::subtract(cell,box({0,0,0},{1,.5,1}),air)&&near(C::volume(air),.5),"Slab removes only lower half");
 check(C::subtract(cell,box({.25,0,.25},{.75,1,.75}),air)&&near(C::volume(air),.75),"Post preserves all surrounding water");
 check(C::subtract(air,box({.25,0,.25},{.75,1,.75}),next)&&near(C::volume(next),.75),"Repeated solid does not double-delete");
 check(C::below(air,.4,next)&&near(C::volume(next),.3),"Removal respects existing partial water head");
 check(C::subtract(cell,box({0,.25,0},{1,.75,1}),air)&&near(C::volume(air),.5),"Overhang preserves water above and below");
 check(C::below(air,.5,next)&&near(C::volume(next),.25),"Lower disconnected interval remains representable");
 auto wedge=box({0,0,0},{1,1,1});wedge.push_back({{0,1,-1},0});
 check(C::subtract(cell,wedge,air)&&near(C::volume(air),.5),"Slope preserves half cell");
 check(C::below(air,.5,next)&&near(C::volume(next),.125),"Sloped partial water volume is exact");
 air=cell;
 for(int i=0;i<4;i++){check(C::subtract(air,box({0,0,i*.25},{1,(i+1)*.25,(i+1)*.25}),next),"Stair component clips");air=next;}
 check(near(C::volume(air),.375),"Four-step stair removes actual volume");
 check(C::subtract(cell,box({1,0,0},{2,1,1}),air)&&near(C::volume(air),1),"Touching solid does not delete water");
 check(C::subtract(cell,box({-1,-1,-1},{2,2,2}),air)&&air.empty(),"Enclosing solid empties cell");
 auto invalid=box({0,0,0},{1,1,1});invalid[0].offset=std::numeric_limits<double>::quiet_NaN();air=cell;
 check(!C::subtract(cell,invalid,air)&&near(C::volume(air),1),"Invalid clipping leaves output unchanged");
 terraforest::WaterCellProfile terrain;terrain.floor={0,500,0,500};terrain.cut=true;
 C::Pieces actual;
 check(terrain.solid_remainder(500,{},actual)&&near(C::volume(actual),.0625),"Runtime terrain wedge converts to exact air volume");
 check(terrain.solid_remainder(250,{},actual)&&near(C::volume(actual),.015625),"Runtime partial head matches terrain volume");
 check(terrain.solid_remainder(500,{box({0,0,0},{.25,.5,.5})},actual)&&near(C::volume(actual),.015625),"Building deletes only water above existing terrain");
 terrain.floor={-500,500,-500,500};
 check(terrain.solid_remainder(500,{},actual)&&near(C::volume(actual)*1000000,terrain.volume(500)),"Floor below cell is clipped without invented water");
 terraforest::WaterSolidProfile cache;
 terrain.floor={0,500,0,500};
 check(terrain.solid_remainder(500,{box({0,.15,0},{.5,.25,.5})},actual)&&cache.prepare(actual),"Prepare cached occupancy for terrain and overhang");
 double worst=0;
 for(int i=0;i<=100;i++){double y=i*.005;C::Pieces reference;C::below(actual,y,reference);worst=std::max(worst,std::abs(cache.volume(y)-C::volume(reference)));}
 check(worst<1e-9,"Cached cubic volume agrees with clipping at 101 heights");
 auto plain=terraforest::WaterCellProfile::make(nullptr,false,0,500);
 check(plain.solid_remainder(500,{box({0,.15,0},{.5,.25,.5})},actual)&&cache.prepare(actual),"Prepare two wet intervals");
 plain.solid=&cache;
 check(plain.capacity()==100000,"Runtime capacity subtracts slab exactly");
 for(auto amount:{1000u,15000u,37499u,37500u,50000u,99999u})check(std::abs(plain.volume(plain.head(amount))-amount)<.01,"Cached head conserves quantity across cavity");
 check(cache.distance({.25,.2,.25},.5)>0&&cache.distance({.25,.1,.25},.5)<0&&cache.distance({.25,.4,.25},.5)<0,"Signed field preserves both intervals and excludes building");
 double bottom=0,top=0;
 check(cache.interval({.25,.1,.25},.5,bottom,top)&&near(bottom,0)&&near(top,.15),"Depth below overhang stops at its underside");
 check(cache.interval({.25,.4,.25},.5,bottom,top)&&near(bottom,.25)&&near(top,.5),"Depth above overhang starts at its top");
 check(!cache.interval({.25,.2,.25},.5,bottom,top),"Solid interior is never water");
 plain.solid=nullptr;
 check(plain.solid_remainder(500,{box({.125,0,.125},{.375,.5,.375})},actual)&&cache.prepare(actual),"Prepare post cache");
 plain.solid=&cache;
 check(plain.field(.25,.25,.25,500)>0&&plain.field(.25,.25,.25,500)<=.25&&plain.field(.05,.25,.05,500)<0,"Runtime field keeps post dry with finite interpolation");
 check(plain.wet_interval(.05,.25,.05,500,bottom,top)&&near(top,.5),"Runtime interval includes surrounding water");
 auto encoded=cache.encode();terraforest::WaterSolidProfile loaded;
 check(loaded.decode(encoded)&&near(loaded.capacity(),cache.capacity())&&near(loaded.volume(.31),cache.volume(.31)),"Prepared occupancy codec preserves exact values");
 auto bad=encoded;bad[0]=1;check(!loaded.decode(bad)&&near(loaded.capacity(),cache.capacity()),"Bad occupancy cache fails atomically");
 bad=encoded;bad.push_back(0);check(!loaded.decode(bad),"Occupancy codec rejects trailing data");
 std::printf("WATER_SOLID_CLIP failures=%d\n",failures);return failures?1:0;
}
