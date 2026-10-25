#include "block_prefab.hpp"
#include "block_word.hpp"
#include <algorithm>
#include <cmath>
#include <map>
#include <tuple>
#include <vector>

namespace terraforest {
namespace {
using PavingCells=std::map<std::tuple<int,int,int>,int>;
PackedInt32Array paving_records(const PavingCells &cells){
    PackedInt32Array records;records.resize(int64_t(cells.size())*4);int offset=0;
    for(const auto &cell:cells){records.set(offset++,std::get<0>(cell.first));records.set(offset++,std::get<2>(cell.first));records.set(offset++,std::get<1>(cell.first));records.set(offset++,cell.second);}
    return records;
}
}
Dictionary NativeBlockPrefab::plan_paving(const Array &roads) const {
    auto failure=[](const char *reason){Dictionary result;result["ok"]=false;result["reason"]=reason;return result;};
    if(roads.is_empty()||roads.size()>8192)return failure("Invalid paving road count");
    struct Road {Vector3 start,finish;double width,length;bool grid_normalized;};
    std::vector<Road> checked;std::vector<Vector3> crossings;
    for(int index=0;index<roads.size();++index){
        if(roads[index].get_type()!=Variant::DICTIONARY)return failure("Invalid paving road");
        Dictionary road=roads[index];
        if(road.get("start",Variant()).get_type()!=Variant::VECTOR3||road.get("finish",Variant()).get_type()!=Variant::VECTOR3)return failure("Missing paving endpoints");
        Variant width_value=road.get("half_width",3.0);
        if(width_value.get_type()!=Variant::INT&&width_value.get_type()!=Variant::FLOAT)return failure("Invalid paving width");
        Vector3 start=road["start"],finish=road["finish"];
        double width=width_value,length=Vector2(finish.x-start.x,finish.z-start.z).length();
        if(!start.is_finite()||!finish.is_finite()||!std::isfinite(width)||width<1||width>16||length<.01||length>2000)return failure("Invalid paving bounds");
        for(Vector3 point:{start,finish})if(point.x<0||point.z<0||point.x>2000||point.z>2000||point.y<1||point.y>255)return failure("Paving outside world");
        checked.push_back({start,finish,width,length,bool(road.get("grid_normalized",false))});
        if(length<2)crossings.push_back((start+finish)*.5);
    }
    PavingCells cells;Array beds;int terrain_ramps=0;
    for(const auto &road:checked){
        if(road.length<2)continue;
        bool along_x=std::abs(road.finish.z-road.start.z)<.001,along_z=std::abs(road.finish.x-road.start.x)<.001;
        bool sloping=std::abs(road.finish.y-road.start.y)>.001;
        if((!along_x&&!along_z)||sloping){++terrain_ramps;continue;}
        int axis=along_x?0:2,lateral=along_x?2:0;
        if(std::abs(road.start.y-std::round(road.start.y))>.001){++terrain_ramps;continue;}
        int begin=int(std::ceil(std::min(road.start[axis],road.finish[axis]))),end=int(std::floor(std::max(road.start[axis],road.finish[axis])));
        int height=int(std::round(road.start.y))-1;
        auto append_bed=[&](int first,int last,double center){
            if(first>=last)return;
            Vector3 start,finish;start[axis]=first;finish[axis]=last;start[lateral]=finish[lateral]=center;start.y=finish.y=road.start.y-(road.grid_normalized?.03:.1);
            double width=.75,clearance=1.;
            Dictionary bed;bed["start"]=start;bed["finish"]=finish;bed["half_width"]=width;bed["depth"]=1.;bed["clearance"]=clearance;bed["shoulder"]=0.;bed["material"]=1;
            Vector3 low=start.min(finish)-Vector3(width,1,width),high=start.max(finish)+Vector3(width,clearance,width);bed["bounds"]=AABB(low,high-low);beds.push_back(bed);
        };
        for(int side:{-1,1}){
            double low=road.start[lateral]+(side<0?-road.width-2:road.width),high=low+2;
            for(int row=int(std::ceil(low));row<int(std::floor(high));++row){
                int run=begin;
                for(int column=begin;column<end;++column){
                    Vector3 point;point[axis]=column+.5;point[lateral]=row+.5;
                    bool crossing=false;
                    for(Vector3 junction:crossings)if(Vector2(point.x-junction.x,point.z-junction.z).length()<road.width+3.5){crossing=true;break;}
                    if(crossing){append_bed(run,column,row+.5);run=column+1;continue;}
                    if(point.x<1||point.z<1||point.x>1999||point.z>1999)return failure("Paving tile outside world");
                    cells[std::make_tuple(int(std::floor(point.x)),int(std::floor(point.z)),height)]=block_word(8,0,2);
                    if(cells.size()>32768)return failure("Paving cell budget exceeded");
                }
                append_bed(run,end,row+.5);
            }
        }
    }
    Dictionary result;result["ok"]=true;result["records"]=paving_records(cells);result["beds"]=beds;result["tiles"]=int64_t(cells.size());result["terrain_ramps"]=terrain_ramps;return result;
}
}
