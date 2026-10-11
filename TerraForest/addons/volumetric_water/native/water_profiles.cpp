// SPDX-License-Identifier: 0BSD
#include "water_profiles.hpp"
#include "water_geometry.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <algorithm>
using namespace godot;
namespace terraforest {
void NativeWaterProfiles::_bind_methods(){
    ClassDB::bind_method(D_METHOD("begin","graph","hierarchy","levels_mm"),&NativeWaterProfiles::begin);
    ClassDB::bind_method(D_METHOD("advance","work_budget"),&NativeWaterProfiles::advance);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterProfiles::statistics);
    ClassDB::bind_method(D_METHOD("profiles"),&NativeWaterProfiles::profiles);
}
void NativeWaterProfiles::fail(const char *why){status=-2;error=why;}
bool NativeWaterProfiles::begin(const Ref<NativeWaterTopology> &graph,const Ref<NativeWaterBasins> &hierarchy,const PackedInt64Array &heights){
    if(status!=-1||graph.is_null()||hierarchy.is_null()||graph->status!=1||hierarchy->status!=1||hierarchy->port_count||hierarchy->root_count!=1||hierarchy->max_depth>64)return false;
    if(heights.size()<2||heights.size()>256||graph->ids.size()!=hierarchy->ids.size()||graph->edges.size()!=hierarchy->edges.size())return false;
    for(int i=0;i<heights.size();++i){
        if(heights[i]<-100000000||heights[i]>100000000||(i&&heights[i]<=heights[i-1]))return false;
    }
    if(double(heights[heights.size()-1])/1000.0>double(graph->source->level_))return false;
    topology=graph;basins=hierarchy;levels=heights;leaves=hierarchy->leaf_count;
    sums.resize(leaves*levels.size(),0);correction.resize(sums.size(),0);rows.resize(leaves);
    for(int i=1;i<levels.size();++i)max_step_mm=std::max(max_step_mm,levels[i]-levels[i-1]);
    status=0;return true;
}
void NativeWaterProfiles::unit(){
    if(phase==0){
        if(cursor==topology->ids.size()){cursor=0;phase=1;return;}
        const int i=cursor++;
        if(topology->ids[i]!=basins->ids[i]||topology->floors[i]!=basins->floors[i]){fail("Hierarchy node geometry does not match its source graph.");return;}
        // Rounded-up air floors can precede actual air by less than one millimetre.
        if(levels[0]>=int64_t(topology->floors[i])){fail("First profile anchor must lie strictly below every air floor.");return;}
        return;
    }
    if(phase==1){
        if(cursor==topology->edges.size()){cursor=0;phase=2;return;}
        if(topology->edges[cursor]!=basins->edges[cursor]){fail("Hierarchy openings do not match source graph.");return;}
        ++cursor;return;
    }
    if(phase==2){
        if(cursor==basins->merges.size()){cursor=0;phase=3;return;}
        const int h=basins->merges[cursor+2];cursor+=4;
        if(!std::binary_search(levels.ptr(),levels.ptr()+levels.size(),int64_t(h))){fail("Every spill elevation requires an exact profile anchor.");return;}
        return;
    }
    if(phase==3){
        if(cursor==topology->ids.size()){cursor=0;anchor=0;phase=4;return;}
        const auto &lake=*topology->source.ptr();
        const int id=topology->ids[cursor],cell=id/6,t=id%6;
        const int x=cell%lake.size_.x,y=(cell/lake.size_.x)%lake.size_.y,z=cell/(lake.size_.x*lake.size_.y);
        if(anchor==0){
            water_clip::Tet input;
            for(int k=0;k<4;++k){const auto p=lake_corner(lake_tets[t][k]);input[k]={double(p.x),double(p.y),double(p.z),double(lake.query_density_[lake.node(x+p.x,y+p.y,z+p.z)])};}
            air_count=water_clip::clip(input,air,true,0);
        }
        const double fill=(double(levels[anchor])/1000.0-double(lake.origin_.y))/lake.spacing_-y;
        double amount=0;std::array<water_clip::Tet,3> water;
        for(int i=0;i<air_count;++i){const int n=water_clip::clip(air[i],water,false,fill);for(int j=0;j<n;++j)amount+=water_clip::volume(water[j]);}
        amount*=double(lake.spacing_)*lake.spacing_*lake.spacing_*1000000.0;
        const int offset=basins->owners[cursor]*levels.size()+anchor;
        const double adjusted=amount-correction[offset],next=sums[offset]+adjusted;
        correction[offset]=(next-sums[offset])-adjusted;sums[offset]=next;
        if(++anchor==levels.size()){anchor=0;++cursor;}return;
    }
    if(phase==4){
        if(cursor==leaves){status=1;phase=5;return;}
        if(anchor==0)rows[cursor].resize(levels.size());
        const double value=sums[cursor*levels.size()+anchor];
        if(!std::isfinite(value)||value<0||value>9007199254740991.0){fail("Capacity exceeds exact quantity range.");return;}
        const int64_t rounded=std::llround(value);
        if((anchor==0&&rounded!=0)||(anchor&&rounded<rows[cursor][anchor-1])){fail("Storage profile is not nonnegative and monotonic from zero.");return;}
        rows[cursor].set(anchor,rounded);
        if(anchor)max_interval_ml=std::max(max_interval_ml,rounded-rows[cursor][anchor-1]);
        if(++anchor==levels.size()){anchor=0;++cursor;}return;
    }
}
Dictionary NativeWaterProfiles::advance(int64_t budget){
    int64_t work=0;if(budget<1||budget>2048){Dictionary out=statistics();out["ok"]=false;out["work_units"]=work;return out;}
    const uint64_t start=Time::get_singleton()->get_ticks_usec();
    while(status==0&&work<budget){unit();++work;++work_total;if(work%32==0&&Time::get_singleton()->get_ticks_usec()-start>=2000)break;}
    Dictionary out=statistics();out["ok"]=status>=0;out["work_units"]=work;return out;
}
Dictionary NativeWaterProfiles::statistics() const {
    Dictionary out;out["status"]=status;out["phase"]=phase;out["leaves"]=leaves;out["anchors"]=levels.size();out["work_units_total"]=work_total;out["error"]=error;
    out["buffer_bytes"]=int64_t((sums.capacity()+correction.capacity())*sizeof(double)+leaves*levels.size()*sizeof(int64_t)+levels.size()*sizeof(int64_t));
    out["max_level_step_mm"]=max_step_mm;out["max_leaf_interval_ml"]=max_interval_ml;out["total_anchor_rounding_bound_ml"]=leaves*.5;return out;
}
Dictionary NativeWaterProfiles::profiles() const {
    Dictionary out;out["ok"]=status==1;if(status!=1)return out;
    Array output;output.resize(leaves);for(int i=0;i<leaves;++i)output[i]=rows[i];
    out["levels_mm"]=levels;out["profiles_ml"]=output;out["merges"]=basins->merges;
    // Monotonic exact geometric capacities and linear interpolation both lie
    // between an interval's endpoints. This is conservative, not a tight error estimate.
    out["max_leaf_interpolation_error_bound_ml"]=double(max_interval_ml)+1.0;
    out["total_anchor_rounding_bound_ml"]=leaves*.5;out["max_level_step_mm"]=max_step_mm;
    return out;
}
}
