// SPDX-License-Identifier: 0BSD
#include "water_topology.hpp"
#include "water_geometry.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <algorithm>
#include <cmath>
#include <limits>
using namespace godot;
namespace terraforest {
namespace {
// Minimum height in the closure of the positive-density portion of a simplex.
// Its open aperture exists strictly above this elevation.
double bottom(const double *height,const double *density,int n){
    double result=std::numeric_limits<double>::infinity();
    for(int a=0;a<n;++a)if(density[a]>0){
        result=std::min(result,height[a]);
        for(int b=0;b<n;++b)if(density[b]<=0){
            const double weight=density[a]/(density[a]-density[b]);
            result=std::min(result,height[a]+weight*(height[b]-height[a]));
        }
    }
    return result;
}
}
void NativeWaterTopology::_bind_methods(){
    ClassDB::bind_method(D_METHOD("begin","volume","first_cell","cells"),&NativeWaterTopology::begin);
    ClassDB::bind_method(D_METHOD("advance","cell_budget"),&NativeWaterTopology::advance);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterTopology::statistics);
    ClassDB::bind_method(D_METHOD("graph"),&NativeWaterTopology::graph);
}
bool NativeWaterTopology::begin(const Ref<NativeLakeVolume> &volume,const Vector3i &start,const Vector3i &size){
    if(source.is_valid()||volume.is_null()||volume->status_!=1)return false;
    for(int a=0;a<3;++a)if(size[a]<1||size[a]>16||start[a]<0||start[a]>volume->size_[a]-size[a])return false;
    first=start;extent=size;count=size.x*size.y*size.z;
    // Bound all storage before advancing: no graph-buffer growth inside slices.
    ids.resize(count*6);floors.resize(count*6);edges.resize(count*6*4*3);
    source=volume;status=0;return true;
}
Dictionary NativeWaterTopology::statistics() const {
    Dictionary out;out["status"]=status;out["processed_cells"]=cursor;out["cells"]=count;
    out["nodes"]=node_count;out["edges"]=edge_count;out["portals"]=portals;
    out["buffer_bytes"]=int64_t((ids.size()+floors.size()+edges.size())*sizeof(int32_t));return out;
}
Dictionary NativeWaterTopology::graph() const {
    Dictionary out;out["ok"]=status==1;if(status!=1)return out;
    out["ids"]=ids;out["floors_mm"]=floors;out["edges"]=edges;return out;
}
Dictionary NativeWaterTopology::advance(int64_t budget){
    if(budget<1||budget>256){Dictionary out=statistics();out["ok"]=false;out["work_cells"]=0;return out;}
    const uint32_t start=cursor;const uint64_t begun=Time::get_singleton()->get_ticks_usec();
    if(status==0){
        const auto &lake=*source.ptr();const auto &links=lake_links();
        auto regional=[&](int x,int y,int z){return x>=first.x&&x<first.x+extent.x&&y>=first.y&&y<first.y+extent.y&&z>=first.z&&z<first.z+extent.z;};
        auto world_mm=[&](double local,int y){return int32_t(std::ceil((double(lake.origin_.y)+(y+local)*lake.spacing_)*1000.0));};
        while(cursor<count&&cursor-start<uint64_t(budget)){
            const uint32_t c=cursor++;const int x=first.x+c%extent.x,y=first.y+(c/extent.x)%extent.y,z=first.z+c/(extent.x*extent.y);
            const uint32_t cell=lake.index(x,y,z);const uint8_t mask=lake.boundary_mask_[cell];
            for(int t=0;t<6;++t)if(mask&(1<<t)){
                double height[4],density[4];
                for(int k=0;k<4;++k){const auto p=lake_corner(lake_tets[t][k]);height[k]=p.y;density[k]=lake.query_density_[lake.node(x+p.x,y+p.y,z+p.z)];}
                const double floor=bottom(height,density,4);
                if(!std::isfinite(floor)||double(lake.origin_.y)+(y+floor)*lake.spacing_>=lake.level_)continue;
                const int32_t id=int32_t(cell*6+t);ids.set(node_count,id);floors.set(node_count++,world_mm(floor,y));
                for(int f=0;f<4;++f){
                    const auto link=links[t][f];const int nx=x+link.x,ny=y+link.y,nz=z+link.z;
                    if(nx<0||ny<0||nz<0||nx>=lake.size_.x||ny>=lake.size_.y||nz>=lake.size_.z)continue;
                    const uint32_t neighbor=lake.index(nx,ny,nz);if(!(lake.boundary_mask_[neighbor]&(1<<link.t)))continue;
                    const int32_t other=int32_t(neighbor*6+link.t);const bool inside=regional(nx,ny,nz);
                    if(inside&&other<id)continue;
                    double h[3],d[3];int n=0;for(int k=0;k<4;++k)if(k!=f){h[n]=height[k];d[n++]=density[k];}
                    const double low=bottom(h,d,3);
                    if(!std::isfinite(low)||double(lake.origin_.y)+(y+low)*lake.spacing_>=lake.level_)continue;
                    edges.set(edge_count*3,std::min(id,other));edges.set(edge_count*3+1,std::max(id,other));edges.set(edge_count*3+2,world_mm(low,y));
                    ++edge_count;if(!inside)++portals;
                }
            }
            if(((cursor-start)&31)==0&&Time::get_singleton()->get_ticks_usec()-begun>=2000)break;
        }
        if(cursor==count){ids.resize(node_count);floors.resize(node_count);edges.resize(edge_count*3);status=1;}
    }
    Dictionary out=statistics();out["ok"]=status>=0;out["work_cells"]=cursor-start;return out;
}
}
