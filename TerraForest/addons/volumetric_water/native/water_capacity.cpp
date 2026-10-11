// SPDX-License-Identifier: 0BSD
#include "water_capacity.hpp"
#include "water_geometry.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <array>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
namespace {
struct Vertex {double x,y,z,d;};
using Tet=std::array<Vertex,4>;
Vertex interpolate(const Vertex &a,const Vertex &b,double weight) {
    return {a.x+(b.x-a.x)*weight,a.y+(b.y-a.y)*weight,a.z+(b.z-a.z)*weight,a.d+(b.d-a.d)*weight};
}
// Clip a convex tetrahedron to a half-space. At most three tetrahedra result.
int clip(const Tet &input,std::array<Tet,3> &out,bool density,double fill) {
    int inside[4],outside[4],ni=0,no=0;double values[4];
    for(int k=0;k<4;++k){values[k]=density?input[k].d:fill-input[k].y;if(values[k]>0)inside[ni++]=k;else outside[no++]=k;}
    if(!ni)return 0;if(ni==4){out[0]=input;return 1;}
    auto edge=[&](int i,int j){return interpolate(input[i],input[j],values[i]/(values[i]-values[j]));};
    const auto a=input[inside[0]];
    if(ni==1){out[0]={a,edge(inside[0],outside[0]),edge(inside[0],outside[1]),edge(inside[0],outside[2])};return 1;}
    const auto b=input[inside[1]];
    if(ni==3){
        const auto c=input[inside[2]],p=edge(inside[0],outside[0]),q=edge(inside[1],outside[0]),r=edge(inside[2],outside[0]);
        out[0]={a,b,c,p};out[1]={b,c,p,q};out[2]={c,p,q,r};return 3;
    }
    const auto p=edge(inside[0],outside[0]),q=edge(inside[0],outside[1]),r=edge(inside[1],outside[0]),s=edge(inside[1],outside[1]);
    out[0]={a,p,q,b};out[1]={p,q,b,r};out[2]={q,b,r,s};return 3;
}
double volume(const Tet &t) {
    const double ax=t[1].x-t[0].x,ay=t[1].y-t[0].y,az=t[1].z-t[0].z;
    const double bx=t[2].x-t[0].x,by=t[2].y-t[0].y,bz=t[2].z-t[0].z;
    const double cx=t[3].x-t[0].x,cy=t[3].y-t[0].y,cz=t[3].z-t[0].z;
    return std::abs(ax*(by*cz-bz*cy)-ay*(bx*cz-bz*cx)+az*(bx*cy-by*cx))/6.0;
}
}
void NativeWaterCapacity::_bind_methods() {
    ClassDB::bind_method(D_METHOD("begin","volume"),&NativeWaterCapacity::begin);
    ClassDB::bind_method(D_METHOD("step","cell_budget"),&NativeWaterCapacity::step);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterCapacity::statistics);
}
bool NativeWaterCapacity::begin(const Ref<NativeLakeVolume> &volume) {
    if(source.is_valid()||volume.is_null()||volume->status_!=1)return false;
    source=volume;status=0;return true;
}
Dictionary NativeWaterCapacity::statistics() const {
    Dictionary out;out["status"]=status;out["processed_cells"]=cursor;
    out["cells"]=source.is_valid()?source->count_:0;
    out["cubic_metres"]=status==1?cubic_metres:0.0;
    out["amount_ml"]=status==1?int64_t(std::llround(cubic_metres*1000000.0)):int64_t(0);
    return out;
}
Dictionary NativeWaterCapacity::step(int64_t budget) {
    if(budget<1||budget>2048){Dictionary out=statistics();out["ok"]=false;out["work_cells"]=0;return out;}
    const uint32_t start=cursor;const uint64_t time=Time::get_singleton()->get_ticks_usec();
    if(status==0){
        const auto &lake=*source.ptr();
        const double fill=(double(lake.level_)-lake.origin_.y)/lake.spacing_;
        const double scale=double(lake.spacing_)*lake.spacing_*lake.spacing_;
        while(cursor<lake.count_&&cursor-start<uint64_t(budget)){
            const uint32_t id=cursor++;const int x=id%lake.size_.x,y=(id/lake.size_.x)%lake.size_.y,z=id/(lake.size_.x*lake.size_.y);
            double cell_volume=0;
            if(lake.wet_[id])cell_volume=std::max(0.0,std::min(1.0,fill-y));
            else if(lake.boundary_mask_[id])for(int t=0;t<6;++t)if(lake.boundary_mask_[id]&(1<<t)){
                Tet input;
                for(int k=0;k<4;++k){const int c=lake_tets[t][k],dx=c&1,dy=(c>>1)&1,dz=(c>>2)&1;input[k]={double(dx),double(dy),double(dz),double(lake.query_density_[lake.node(x+dx,y+dy,z+dz)])};}
                std::array<Tet,3> air,water;const int count=clip(input,air,true,0);
                for(int i=0;i<count;++i){const int n=clip(air[i],water,false,fill-y);for(int j=0;j<n;++j)cell_volume+=volume(water[j]);}
            }
            // Compensated accumulation is deterministic across scheduler budgets.
            const double adjusted=cell_volume*scale-compensation,next=cubic_metres+adjusted;
            compensation=(next-cubic_metres)-adjusted;cubic_metres=next;
            if(((cursor-start)&31)==0&&Time::get_singleton()->get_ticks_usec()-time>=2000)break;
        }
        if(cursor==lake.count_)status=1;
    }
    Dictionary out=statistics();out["ok"]=status>=0;out["work_cells"]=cursor-start;return out;
}
}
