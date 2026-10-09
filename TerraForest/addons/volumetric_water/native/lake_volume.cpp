#include "lake_volume.hpp"
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <new>
#include <vector>

using namespace godot;
namespace terraforest {
void NativeLakeVolume::_bind_methods() {
    ClassDB::bind_method(D_METHOD("cache_identity","core","compatibility"), &NativeLakeVolume::cache_identity);
    ClassDB::bind_method(D_METHOD("capture_bake","identity"), &NativeLakeVolume::capture_bake);
    ClassDB::bind_method(D_METHOD("restore_bake","bytes","identity"), &NativeLakeVolume::restore_bake);
    ClassDB::bind_method(D_METHOD("configure", "origin", "cells", "spacing", "fill_level", "seed"), &NativeLakeVolume::configure);
    ClassDB::bind_method(D_METHOD("bake_density", "density"), &NativeLakeVolume::bake_density);
    ClassDB::bind_method(D_METHOD("sample_terrain", "core", "budget", "revision", "epoch"), &NativeLakeVolume::sample_terrain);
    ClassDB::bind_method(D_METHOD("contains", "point"), &NativeLakeVolume::contains);
    ClassDB::bind_method(D_METHOD("submerges_root", "point"), &NativeLakeVolume::submerges_root);
    ClassDB::bind_method(D_METHOD("depth_at", "point"), &NativeLakeVolume::depth_at);
    ClassDB::bind_method(D_METHOD("surface_arrays"), &NativeLakeVolume::surface_arrays);
    ClassDB::bind_method(D_METHOD("smooth_surface_arrays"), &NativeLakeVolume::smooth_surface_arrays);
    ClassDB::bind_method(D_METHOD("statistics"), &NativeLakeVolume::statistics);
    ClassDB::bind_method(D_METHOD("bounds"), &NativeLakeVolume::bounds);
}
uint32_t NativeLakeVolume::index(int x, int y, int z) const { return uint32_t(x + size_.x * (y + size_.y * z)); }
uint32_t NativeLakeVolume::node(int x, int y, int z) const { return uint32_t(x + (size_.x+1) * (y + (size_.y+1) * z)); }

bool NativeLakeVolume::configure(const Vector3 &origin, const Vector3i &cells, double spacing, double level, const Vector3 &seed) {
    // One-shot builder prevents mutation of a published volume by a retained reference.
    if (count_ || !origin.is_finite() || !seed.is_finite() || !std::isfinite(level) ||
        !std::isfinite(spacing) || spacing < 1 || spacing > 8 || cells.x < 3 || cells.y < 3 || cells.z < 3 ||
        cells.x > 128 || cells.y > 64 || cells.z > 128) return false;
    const int64_t count = int64_t(cells.x)*cells.y*cells.z;
    const int64_t nodes = int64_t(cells.x+1)*(cells.y+1)*(cells.z+1);
    if (count > 262144 || origin.abs().length() > 100000 ||
        level <= origin.y || level >= origin.y + cells.y*spacing) return false;
    const Vector3 local = (seed-origin)/spacing;
    if (local.x<0 || local.y<0 || local.z<0 || local.x>=cells.x || local.y>=cells.y || local.z>=cells.z || seed.y>=level) return false;
    std::unique_ptr<float[]> density(new(std::nothrow) float[size_t(nodes)]);
    std::unique_ptr<uint8_t[]> wet(new(std::nothrow) uint8_t[size_t(count)]());
    std::unique_ptr<uint32_t[]> queue(new(std::nothrow) uint32_t[size_t(count)]);
    if (!density || !wet || !queue) return false;
    origin_=origin; seed_=seed; size_=cells; spacing_=float(spacing); level_=float(level);
    count_=uint32_t(count); node_count_=uint32_t(nodes); status_=0;
    density_=std::move(density); wet_=std::move(wet); queue_=std::move(queue);
    return true;
}
bool NativeLakeVolume::eligible(int x, int y, int z) const {
    if (origin_.y + y*spacing_ >= level_) return false;
    // All eight corners must be air. This deliberately leaves a dry shoreline
    // margin of up to a voxel; no surface is knowingly drawn through solid cells.
    for (int dz=0;dz<2;++dz) for(int dy=0;dy<2;++dy) for(int dx=0;dx<2;++dx)
        if (density_[node(x+dx,y+dy,z+dz)] <= 0) return false;
    return true;
}
int NativeLakeVolume::bake_density(const PackedFloat32Array &density) {
    if (status_ != 0 || sampled_ || density.size()!=node_count_) return -1;
    for (int64_t i=0;i<density.size();++i) if (!std::isfinite(density[i])) return -1;
    std::copy(density.ptr(),density.ptr()+node_count_,density_.get());
    sampled_=node_count_;
    return finish();
}
static PackedByteArray command(uint32_t code) {
    PackedByteArray packet; packet.resize(4); packet.encode_u32(0,code); return packet;
}
static bool reply_ok(const PackedByteArray &reply, int length) {
    return reply.size()>=length && reply.decode_u32(0)==0x32505254 && reply.decode_u32(8)==0;
}
int NativeLakeVolume::sample_terrain(Object *core, int64_t budget, int64_t revision, int64_t epoch) {
    if (status_!=0 || !core || !core->has_method("execute") || budget<1 || budget>2048 || revision<0 || epoch<0) return -1;
    // Legacy terrain samples integer lattice points. Reject fractional grids
    // instead of silently baking a shifted, repeated density field.
    if (origin_ != origin_.floor() || spacing_ != std::floor(spacing_) ||
        origin_.x<0 || origin_.y<1 || origin_.z<0 || bounds().get_end().x>2000 ||
        bounds().get_end().y>255 || bounds().get_end().z>2000) return status_=-1;
    const PackedByteArray info=core->call("execute",command(0));
    const PackedByteArray cancel=core->call("execute",command(13));
    if (!reply_ok(info,16) || !reply_ok(cancel,16) || info.decode_u32(12)!=uint64_t(revision) || cancel.decode_u32(12)!=uint64_t(epoch)) return status_=-4;
    PackedByteArray packet; packet.resize(16); packet.encode_u32(0,7);
    const uint64_t start=Time::get_singleton()->get_ticks_usec();
    for (int64_t i=0;i<budget && sampled_<node_count_;++i) {
        const uint32_t x=sampled_%(size_.x+1), y=(sampled_/(size_.x+1))%(size_.y+1), z=sampled_/((size_.x+1)*(size_.y+1));
        const Vector3 p=origin_+Vector3(x,y,z)*spacing_;
        packet.encode_float(4,p.x); packet.encode_float(8,p.y); packet.encode_float(12,p.z);
        const PackedByteArray reply=core->call("execute",packet);
        if (!reply_ok(reply,20) || !std::isfinite(reply.decode_float(16))) return status_=-1;
        density_[sampled_++]=reply.decode_float(16);
        if ((i&31)==31 && Time::get_singleton()->get_ticks_usec()-start>=2000) break;
    }
    const PackedByteArray after=core->call("execute",command(13));
    if (!reply_ok(after,16) || after.decode_u32(12)!=uint64_t(epoch)) return status_=-4;
    return sampled_==node_count_ ? finish() : 0;
}
int NativeLakeVolume::finish() {
    const Vector3 local=(seed_-origin_)/spacing_;
    const int sx=int(std::floor(local.x)), sy=int(std::floor(local.y)), sz=int(std::floor(local.z));
    if (!eligible(sx,sy,sz)) { status_=-2; density_.reset(); queue_.reset(); return status_; }
    uint32_t head=0, tail=1;
    queue_[0]=index(sx,sy,sz); wet_[queue_[0]]=1;
    constexpr int delta[6][3]={{-1,0,0},{1,0,0},{0,-1,0},{0,1,0},{0,0,-1},{0,0,1}};
    while(head<tail) {
        const uint32_t id=queue_[head++];
        const int x=id%size_.x, y=(id/size_.x)%size_.y, z=id/(size_.x*size_.y);
        if (x==0 || z==0 || y==0 || x==size_.x-1 || z==size_.z-1) {
            status_=-3; wet_.reset(); density_.reset(); queue_.reset(); return status_;
        }
        for (const auto &d:delta) {
            const int nx=x+d[0],ny=y+d[1],nz=z+d[2];
            if(nx<0||ny<0||nz<0||nx>=size_.x||ny>=size_.y||nz>=size_.z)continue;
            const uint32_t next=index(nx,ny,nz);
            if (!wet_[next] && eligible(nx,ny,nz)) { wet_[next]=1; queue_[tail++]=next; }
        }
    }
    column_top_.reset(new(std::nothrow) uint8_t[size_t(size_.x)*size_.z]());
    if(!column_top_){status_=-1;wet_.reset();density_.reset();queue_.reset();return status_;}
    for(uint32_t i=0;i<tail;++i){
        const uint32_t id=queue_[i];const int x=id%size_.x,y=(id/size_.x)%size_.y,z=id/(size_.x*size_.y);
        auto &top=column_top_[x+size_.x*z];top=std::max(top,uint8_t(y+1));
    }
    wet_count_=tail; status_=1;
    smooth_surface_=build_smooth_surface();
    density_.reset(); queue_.reset();
    return status_;
}
bool NativeLakeVolume::contains(const Vector3 &p) const {
    if(status_!=1 || !p.is_finite() || p.y>=level_)return false;
    const Vector3 v=(p-origin_)/spacing_;
    if(v.x<0||v.y<0||v.z<0||v.x>=size_.x||v.y>=size_.y||v.z>=size_.z)return false;
    return wet_[index(int(std::floor(v.x)),int(std::floor(v.y)),int(std::floor(v.z)))]!=0;
}
double NativeLakeVolume::depth_at(const Vector3 &point) const { return contains(point) ? level_-point.y : 0.0; }
bool NativeLakeVolume::submerges_root(const Vector3 &p) const {
    if(status_!=1||!p.is_finite()||p.y>=level_||p.y<origin_.y)return false;
    const Vector3 v=(p-origin_)/spacing_;
    if(v.x<0||v.z<0||v.x>=size_.x||v.z>=size_.z)return false;
    const uint8_t top=column_top_[int(std::floor(v.x))+size_.x*int(std::floor(v.z))];
    return top && p.y<std::min(level_,origin_.y+top*spacing_);
}
AABB NativeLakeVolume::bounds() const { return AABB(origin_,Vector3(size_)*spacing_); }
Array NativeLakeVolume::surface_arrays() const {
    Array arrays; arrays.resize(Mesh::ARRAY_MAX);
    if(status_!=1)return arrays;
    PackedVector3Array vertices,normals; PackedVector2Array uv; PackedInt32Array indices;
    const int y=int(std::ceil((level_-origin_.y)/spacing_))-1;
    // A bounded local mask keeps extraction read-only on published volumes.
    // Merge rectangles in X/Z without bridging dry cells, islands or cave roofs.
    // Each cell is emitted once; rectangular lakes reduce to a single quad.
    std::array<uint8_t,128*128> surface{};
    for(int z=0;z<size_.z;++z) for(int x=0;x<size_.x;++x)
        surface[x+size_.x*z]=wet_[index(x,y,z)];
    for(int z=0;z<size_.z;++z) for(int x=0;x<size_.x;++x) {
        if(!surface[x+size_.x*z])continue;
        int end_x=x+1;
        while(end_x<size_.x && surface[end_x+size_.x*z])++end_x;
        int end_z=z+1;
        while(end_z<size_.z) {
            bool complete=true;
            for(int scan=x;scan<end_x;++scan) if(!surface[scan+size_.x*end_z]){complete=false;break;}
            if(!complete)break;
            ++end_z;
        }
        for(int row=z;row<end_z;++row)
            std::fill(surface.begin()+x+size_.x*row,surface.begin()+end_x+size_.x*row,0);
        const float x0=origin_.x+x*spacing_,x1=origin_.x+end_x*spacing_,z0=origin_.z+z*spacing_,z1=origin_.z+end_z*spacing_;
        const int base=int(vertices.size());
        vertices.push_back(Vector3(x0,level_,z0)); vertices.push_back(Vector3(x1,level_,z0));
        vertices.push_back(Vector3(x1,level_,z1)); vertices.push_back(Vector3(x0,level_,z1));
        for(int k=0;k<4;++k){normals.push_back(Vector3(0,1,0)); const Vector3 p=vertices[base+k]; uv.push_back(Vector2(p.x,p.z));}
        for(int k:{0,1,2,0,2,3})indices.push_back(base+k);
    }
    arrays[Mesh::ARRAY_VERTEX]=vertices; arrays[Mesh::ARRAY_NORMAL]=normals; arrays[Mesh::ARRAY_TEX_UV]=uv; arrays[Mesh::ARRAY_INDEX]=indices;
    return arrays;
}
#include "lake_surface.hpp"
#include "lake_bake.hpp"
Dictionary NativeLakeVolume::statistics() const {
    Dictionary d; d["status"]=status_; d["cells"]=count_; d["sampled_nodes"]=sampled_; d["total_nodes"]=node_count_;
    d["wet_cells"]=wet_count_; d["resident_bytes"]=wet_ ? count_ : 0;
    d["builder_bytes"]=(density_ ? node_count_*sizeof(float):0)+(queue_ ? count_*sizeof(uint32_t):0);
    d["query_index_bytes"]=column_top_ ? size_.x*size_.z : 0;
    d["surface_bytes"]=smooth_surface_.size()==Mesh::ARRAY_MAX ?
        PackedVector3Array(smooth_surface_[Mesh::ARRAY_VERTEX]).size()*32+PackedInt32Array(smooth_surface_[Mesh::ARRAY_INDEX]).size()*4 : 0;
    d["fill_level"]=level_; d["spacing"]=spacing_; d["dynamic_flow"]=false; return d;
}
}
