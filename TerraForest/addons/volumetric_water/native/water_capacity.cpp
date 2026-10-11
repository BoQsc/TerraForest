// SPDX-License-Identifier: 0BSD
#include "water_capacity.hpp"
#include "water_geometry.hpp"
#include "water_clip.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <array>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
using namespace water_clip;
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
