// SPDX-License-Identifier: 0BSD
#include "water_field.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
using namespace godot;
namespace terraforest {
void NativeWaterField::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","world_id","geometry_revision","grid_origin","cells","spacing","ceiling_mm","density"),&NativeWaterField::configure);
    ClassDB::bind_method(D_METHOD("begin_terrain","world_id","geometry_revision","cancel_epoch","grid_origin","cells","spacing","ceiling_mm"),&NativeWaterField::begin_terrain);
    ClassDB::bind_method(D_METHOD("sample_terrain","core","node_budget"),&NativeWaterField::sample_terrain);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterField::statistics);
}
bool NativeWaterField::metadata(int64_t id,int64_t rev,const Vector3i &start,const Vector3i &size,int64_t scale,int64_t top){
    if(status!=-1||id<1||rev<0||scale<1||scale>8||top<-100000000||top>100000000)return false;
    for(int a=0;a<3;++a)if(size[a]<3||size[a]>18||int64_t(start[a])*scale<-100000|| (int64_t(start[a])+size[a])*scale>100000)return false;
    // A shared world ceiling may be above or below this local region.
    // Clipping belongs to topology; vertical neighbours must share the same head range.
    world=id;revision=rev;origin=start;cells=size;spacing=scale;ceiling=top;return true;
}
bool NativeWaterField::configure(int64_t id,int64_t rev,const Vector3i &start,const Vector3i &size,int64_t scale,int64_t top,const PackedFloat32Array &samples){
    // Bound sizes before multiplication or scanning caller data.
    for(int a=0;a<3;++a)if(size[a]<3||size[a]>18)return false;
    if(samples.size()!=int64_t(size.x+1)*(size.y+1)*(size.z+1))return false;
    for(int i=0;i<samples.size();++i)if(!std::isfinite(samples[i])||std::abs(samples[i])>1000000)return false;
    if(!metadata(id,rev,start,size,scale,top))return false;
    density=samples;status=1;sampled=samples.size();return true;
}
bool NativeWaterField::begin_terrain(int64_t id,int64_t rev,int64_t cancel,const Vector3i &start,const Vector3i &size,int64_t scale,int64_t top){
    if(cancel<0||cancel>UINT32_MAX||rev<0||rev>UINT32_MAX||scale<1||scale>8)return false;
    // The current terrain API samples integer points in a bounded legacy domain.
    if(int64_t(start.x)*scale<0||int64_t(start.y)*scale<1||int64_t(start.z)*scale<0||
       (int64_t(start.x)+size.x)*scale>2000||(int64_t(start.y)+size.y)*scale>255||(int64_t(start.z)+size.z)*scale>2000)return false;
    if(!metadata(id,rev,start,size,scale,top))return false;
    epoch=cancel;density.resize((cells.x+1)*(cells.y+1)*(cells.z+1));status=0;return true;
}
int NativeWaterField::sample_terrain(Object *core,int64_t budget){
    if(status!=0||!core||!core->has_method("execute")||budget<1||budget>2048)return -1;
    if(core_id&&core_id!=core->get_instance_id())return status=-4;
    core_id=core->get_instance_id();
    auto valid=[](const PackedByteArray &reply,int length){return reply.size()>=length&&reply.decode_u32(0)==0x32505254&&reply.decode_u32(8)==0;};
    auto current=[&](){
        PackedByteArray packet;packet.resize(4);packet.encode_u32(0,0);const PackedByteArray info=core->call("execute",packet);
        packet.encode_u32(0,13);const PackedByteArray cancel=core->call("execute",packet);
        return valid(info,16)&&valid(cancel,16)&&info.decode_u32(12)==uint64_t(revision)&&cancel.decode_u32(12)==uint64_t(epoch);
    };
    if(!current())return status=-4;
    PackedByteArray packet;packet.resize(16);packet.encode_u32(0,7);
    const uint64_t begun=Time::get_singleton()->get_ticks_usec();
    for(int64_t i=0;i<budget&&sampled<density.size();++i){
        const int x=sampled%(cells.x+1),y=(sampled/(cells.x+1))%(cells.y+1),z=sampled/((cells.x+1)*(cells.y+1));
        packet.encode_float(4,(origin.x+x)*spacing);packet.encode_float(8,(origin.y+y)*spacing);packet.encode_float(12,(origin.z+z)*spacing);
        const PackedByteArray reply=core->call("execute",packet);
        if(!valid(reply,20)||!std::isfinite(reply.decode_float(16))||std::abs(reply.decode_float(16))>1000000)return status=-2;
        density.set(sampled++,reply.decode_float(16));
        if((i&31)==31&&Time::get_singleton()->get_ticks_usec()-begun>=2000)break;
    }
    if(!current())return status=-4;
    if(sampled==density.size())status=1;
    return status;
}
Dictionary NativeWaterField::statistics() const {
    Dictionary d;d["ready"]=status==1;d["status"]=status;d["sampled_nodes"]=sampled;d["world_id"]=world;d["revision"]=revision;d["cancel_epoch"]=epoch;d["grid_origin"]=origin;d["cells"]=cells;d["spacing"]=spacing;d["ceiling_mm"]=ceiling;d["density_bytes"]=density.size()*4;return d;
}
}
