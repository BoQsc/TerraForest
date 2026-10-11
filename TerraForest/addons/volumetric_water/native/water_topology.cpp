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
    ClassDB::bind_method(D_METHOD("begin_field","field","first_cell","cells"),&NativeWaterTopology::begin_field);
    ClassDB::bind_method(D_METHOD("begin_join","regions"),&NativeWaterTopology::begin_join);
    ClassDB::bind_method(D_METHOD("advance_join","work_budget"),&NativeWaterTopology::advance_join);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterTopology::statistics);
    ClassDB::bind_method(D_METHOD("graph"),&NativeWaterTopology::graph);
}
bool NativeWaterTopology::begin(const Ref<NativeLakeVolume> &volume,const Vector3i &start,const Vector3i &size){
    if(source.is_valid()||field.is_valid()||volume.is_null()||volume->status_!=1)return false;
    for(int a=0;a<3;++a)if(size[a]<1||size[a]>16||start[a]<0||start[a]>volume->size_[a]-size[a])return false;
    first=start;extent=size;count=size.x*size.y*size.z;
    // Bound all storage before advancing: no graph-buffer growth inside slices.
    ids.resize(count*6);floors.resize(count*6);edges.resize(count*6*4*3);
    source=volume;status=0;return true;
}
WaterDensityView NativeWaterTopology::view() const {
    if(field.is_valid())return {Vector3(field->origin)*field->spacing,field->cells,double(field->spacing),double(field->ceiling)/1000.0,field->density.ptr(),nullptr};
    return {source->origin_,source->size_,double(source->spacing_),double(source->level_),source->query_density_.get(),source->boundary_mask_.get()};
}
bool NativeWaterTopology::begin_field(const Ref<NativeWaterField> &input,const Vector3i &start,const Vector3i &size){
    if(source.is_valid()||field.is_valid()||input.is_null()||input->status!=1)return false;
    // All owned cells require a sampled neighbour, even at an open domain edge.
    for(int a=0;a<3;++a)if(size[a]<1||size[a]>16||start[a]<1||start[a]>input->cells[a]-1-size[a])return false;
    field=input;first=start;extent=size;count=size.x*size.y*size.z;
    ids.resize(count*6);floors.resize(count*6);edges.resize(count*6*4*3);
    world_ports.resize(4*(size.x*size.y+size.x*size.z+size.y*size.z)*9);status=0;return true;
}
Dictionary NativeWaterTopology::statistics() const {
    Dictionary out;out["status"]=status;out["processed_cells"]=cursor;out["cells"]=count;
    out["nodes"]=node_count;out["edges"]=edge_count;out["portals"]=portals;out["joined"]=joined;out["join_work_total"]=join_work;
    out["buffer_bytes"]=int64_t((ids.size()+floors.size()+edges.size()+world_ports.size())*sizeof(int32_t));return out;
}
Dictionary NativeWaterTopology::graph() const {
    Dictionary out;out["ok"]=status==1;if(status!=1)return out;
    out["ids"]=ids;out["floors_mm"]=floors;out["edges"]=edges;
    if(field.is_valid()){
        out["world_id"]=field->world;out["revision"]=field->revision;out["cancel_epoch"]=field->epoch;out["ceiling_mm"]=field->ceiling;out["grid_origin"]=field->origin;out["spacing"]=field->spacing;out["world_ports"]=world_ports;
    }
    return out;
}
Dictionary NativeWaterTopology::advance(int64_t budget){
    if(joined||budget<1||budget>256){Dictionary out=statistics();out["ok"]=false;out["work_cells"]=0;return out;}
    const uint32_t start=cursor;const uint64_t begun=Time::get_singleton()->get_ticks_usec();
    if(status==0){
        const auto lake=view();const auto &links=lake_links();
        auto regional=[&](int x,int y,int z){return x>=first.x&&x<first.x+extent.x&&y>=first.y&&y<first.y+extent.y&&z>=first.z&&z<first.z+extent.z;};
        auto world_mm=[&](double local,int y){const double base=field.is_valid()?double(int64_t(field->origin.y)+y)*lake.spacing:double(lake.origin.y)+y*lake.spacing;return int32_t(std::ceil((base+local*lake.spacing)*1000.0));};
        while(cursor<count&&cursor-start<uint64_t(budget)){
            const uint32_t c=cursor++;const int x=first.x+c%extent.x,y=first.y+(c/extent.x)%extent.y,z=first.z+c/(extent.x*extent.y);
            const uint32_t cell=lake.cell(x,y,z);const uint8_t mask=lake.mask?lake.mask[cell]:63;
            for(int t=0;t<6;++t)if(mask&(1<<t)){
                double height[4],density[4];
                for(int k=0;k<4;++k){const auto p=lake_corner(lake_tets[t][k]);height[k]=p.y;density[k]=lake.density[lake.node(x+p.x,y+p.y,z+p.z)];}
                const double floor=bottom(height,density,4);
                if(!std::isfinite(floor)||double(lake.origin.y)+(y+floor)*lake.spacing>=lake.ceiling)continue;
                const int32_t id=int32_t(cell*6+t);ids.set(node_count,id);floors.set(node_count++,world_mm(floor,y));
                for(int f=0;f<4;++f){
                    const auto link=links[t][f];const int nx=x+link.x,ny=y+link.y,nz=z+link.z;
                    if(nx<0||ny<0||nz<0||nx>=lake.size.x||ny>=lake.size.y||nz>=lake.size.z)continue;
                    const uint32_t neighbor=lake.cell(nx,ny,nz);if(lake.mask&&!(lake.mask[neighbor]&(1<<link.t)))continue;
                    const int32_t other=int32_t(neighbor*6+link.t);const bool inside=regional(nx,ny,nz);
                    if(inside&&other<id)continue;
                    double h[3],d[3];int n=0;for(int k=0;k<4;++k)if(k!=f){h[n]=height[k];d[n++]=density[k];}
                    const double low=bottom(h,d,3);
                    if(!std::isfinite(low)||double(lake.origin.y)+(y+low)*lake.spacing>=lake.ceiling)continue;
                    edges.set(edge_count*3,std::min(id,other));edges.set(edge_count*3+1,std::max(id,other));edges.set(edge_count*3+2,world_mm(low,y));
                    ++edge_count;if(!inside){
                        if(field.is_valid()){
                            const Vector3i a=field->origin+Vector3i(x,y,z),b=field->origin+Vector3i(nx,ny,nz);
                            const int offset=portals*9;
                            for(int axis=0;axis<3;++axis){world_ports.set(offset+axis,a[axis]);world_ports.set(offset+4+axis,b[axis]);}
                            world_ports.set(offset+3,t);world_ports.set(offset+7,link.t);world_ports.set(offset+8,world_mm(low,y));
                        }
                        ++portals;
                    }
                }
            }
            if(((cursor-start)&31)==0&&Time::get_singleton()->get_ticks_usec()-begun>=2000)break;
        }
        if(cursor==count){ids.resize(node_count);floors.resize(node_count);edges.resize(edge_count*3);if(field.is_valid())world_ports.resize(portals*9);status=1;}
    }
    Dictionary out=statistics();out["ok"]=status>=0;out["work_cells"]=cursor-start;return out;
}
}
