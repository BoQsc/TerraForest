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
    WaterCellProfile film;film.floor={0,30,0,30};
    require(film.surface(film.head(1000),0,0)==film.surface(film.head(1000),1,0),"static top stays horizontal above a sloping floor");
    for(uint64_t ml:{1u,100u,1000u,6000u})require(std::abs(partial.volume(partial.head(ml))-ml)<0.03,"static partial-top inversion conserves volume");
    float crossing_bottom[8]={0.1f,-0.1f,0.6f,0.4f,0.1f,-0.1f,0.6f,0.4f};
    auto bottom_cut=WaterCellProfile::make(crossing_bottom,true,100,500);
    require(bottom_cut.cut&&bottom_cut.open_bottom&&std::abs(double(bottom_cut.capacity())-118750)<2,"partial bottom clips the interpolated floor instead of inventing a ramp");
    require(bottom_cut.bottom(0.25,0.5)==0&&std::abs(bottom_cut.bottom(0.75,0.5)-50)<0.001,"partial bottom retains a finite open face and real uphill terrain");
    for(uint64_t ml:{1u,100u,1000u,50000u,118000u})require(std::abs(bottom_cut.volume(bottom_cut.head(ml))-ml)<0.03,"static partial-bottom surface preserves volume within the cell");
    for(auto shape:{partial,bottom_cut}){
        double h=490,reference=0;constexpr int samples=400;
        for(int z=0;z<samples;++z)for(int x=0;x<samples;++x){double u=(x+0.5)/samples,v=(z+0.5)/samples;
            reference+=std::max(0.0,shape.surface(h,u,v)-shape.bottom(u,v))*250/(samples*samples);}
        require(std::abs(reference-shape.volume(h))<1.0,"clipped static volume agrees with independent dense area quadrature within one millilitre");
    }
    float zero_density[8]={};auto unknown=WaterCellProfile::make(zero_density,true,500,500);
    require(unknown.capacity()==0,"zero-density ambiguity does not invent fully open space");
    auto fractional=film;fractional.floor[0]+=0.123;
 require(fractional.head(fractional.capacity())==500,"integer-capacity saturation reaches the top despite sub-millilitre rounding");
 auto adjacent=film;for(double &y:adjacent.floor)y+=30;
    require(WaterCellProfile::face_overlap(film,film.head(10000),adjacent,adjacent.head(10000),0,1),"sufficient static volumes meet across a shared sloping floor face");
    auto barrier=adjacent;barrier.floor.fill(500);
    require(!WaterCellProfile::face_overlap(film,film.head(1000),barrier,500,0,1),"coherence never bridges a solid face");
    auto lower=partial;
    auto upper=bottom_cut;
    require(WaterCellProfile::vertical_overlap(lower,504,upper,4),"static volumes connect through a narrow partial vertical opening");
    require(!WaterCellProfile::vertical_overlap(lower,504,upper,-10),"a dry vertical gap stays disconnected");
    std::puts("WATER_CELL_PROFILE failures=0");
}
