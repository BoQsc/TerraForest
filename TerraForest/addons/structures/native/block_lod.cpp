#include "block_world.hpp"
#include "third_party/meshoptimizer/allocator.cpp"
#include "third_party/meshoptimizer/simplifier.cpp"
#include <algorithm>
#include <chrono>
#include <cstring>
#include <unordered_map>

namespace terraforest {
namespace {
struct VertexHash {
    size_t operator()(const std::array<uint32_t,10> &key) const {
        size_t hash=2166136261u;
        for(auto part:key)hash=(hash^part)*16777619u;
        return hash;
    }
};
std::array<uint32_t,10> vertex_key(const BlockVertex &vertex) {
    std::array<uint32_t,10> key;std::memcpy(key.data(),&vertex,sizeof(vertex));
    for(auto &part:key)if(part==0x80000000u)part=0;
    return key;
}
float tile_offset(const BlockVertex &first,const BlockVertex &second,const BlockVertex &third,int horizontal,int vertical,bool texture_vertical) {
    const float positions[][3]={{first.x,first.y,first.z},{second.x,second.y,second.z},{third.x,third.y,third.z}};
    const float horizontal_first=positions[1][horizontal]-positions[0][horizontal],vertical_first=positions[1][vertical]-positions[0][vertical];
    const float horizontal_second=positions[2][horizontal]-positions[0][horizontal],vertical_second=positions[2][vertical]-positions[0][vertical];
    const float determinant=horizontal_first*vertical_second-horizontal_second*vertical_first;
    if(std::abs(determinant)<1e-9f)return 0;
    const float texture_origin=texture_vertical?first.v:first.u;
    const float texture_first=(texture_vertical?second.v:second.u)-texture_origin,texture_second=(texture_vertical?third.v:third.u)-texture_origin;
    const float gradient_horizontal=(texture_first*vertical_second-texture_second*vertical_first)/determinant;
    const float gradient_vertical=(horizontal_first*texture_second-horizontal_second*texture_first)/determinant;
    const float offset=texture_origin-gradient_horizontal*positions[0][horizontal]-gradient_vertical*positions[0][vertical];
    return std::floor(offset+1e-5f);
}
}
void bake_block_lods(BlockBake &bake) {
    if(bake.indices.size()<96||bake.indices.size()>196608)return;
    const auto start=std::chrono::steady_clock::now();
    std::unordered_map<std::array<uint32_t,10>,unsigned int,VertexHash> welded;
    std::vector<unsigned int> source;
    std::vector<BlockVertex> vertices;
    welded.reserve(bake.vertices.size());source.reserve(bake.indices.size());
    std::vector<unsigned char> locked;
    for(size_t offset=0;offset<bake.indices.size();offset+=3) {
        const auto &first=bake.vertices[bake.indices[offset]],&second=bake.vertices[bake.indices[offset+1]],&third=bake.vertices[bake.indices[offset+2]];
        Vector3 normal=Vector3(second.x-first.x,second.y-first.y,second.z-first.z).cross(Vector3(third.x-first.x,third.y-first.y,third.z-first.z));
        int axis=normal.abs().max_axis_index(),horizontal=axis==0?2:0,vertical=axis==1?2:1;
        float offset_u=tile_offset(first,second,third,horizontal,vertical,false),offset_v=tile_offset(first,second,third,horizontal,vertical,true);
        for(int corner=0;corner<3;++corner) {
            auto vertex=bake.vertices[bake.indices[offset+corner]];vertex.u-=offset_u;vertex.v-=offset_v;
            auto inserted=welded.emplace(vertex_key(vertex),unsigned(vertices.size()));
            if(inserted.second) {
                vertices.push_back(vertex);
                locked.push_back(vertex.x<1e-5f||vertex.y<1e-5f||vertex.z<1e-5f||vertex.x>15.99999f||vertex.y>15.99999f||vertex.z>15.99999f);
            }
            source.push_back(inserted.first->second);
        }
    }
    welded.clear();
    for(size_t index=0;index<bake.vertices.size();++index)welded.emplace(vertex_key(bake.vertices[index]),unsigned(index));
    const float weights[]={.5f,.5f,.5f,.25f,.25f,1.f};
    const float limits[]={.005f,.02f,.06f};
    const float minimum_errors[]={.025f,.06f,.15f};
    size_t previous=source.size();
    for(int level=0;level<3;++level) {
        std::vector<unsigned int> indices(source.size());float error=0;
        size_t count=meshopt_simplifyWithAttributes(indices.data(),source.data(),source.size(),&vertices[0].x,vertices.size(),sizeof(BlockVertex),
            &vertices[0].nx,sizeof(BlockVertex),weights,6,locked.data(),source.size()>>(level+1),limits[level],
            meshopt_SimplifyLockBorder|meshopt_SimplifyErrorAbsolute,&error);
        if(count<12||count>=previous*9/10)continue;
        BlockLod lod;lod.error=std::max(error*2,minimum_errors[level]);lod.indices.reserve(count);
        for(size_t index=0;index<count;++index) {
            const auto &vertex=vertices[indices[index]];
            auto inserted=welded.emplace(vertex_key(vertex),unsigned(bake.vertices.size()));
            if(inserted.second)bake.vertices.push_back(vertex);
            lod.indices.push_back(int32_t(inserted.first->second));
        }
        bake.lods.push_back(std::move(lod));previous=count;
    }
    if(!bake.lods.empty()) {
        std::vector<BlockVertex> original=std::move(bake.vertices);
        std::vector<int32_t> remap(original.size(),-1);welded.clear();
        auto compact=[&](std::vector<int32_t> &indices) {
            for(auto &index:indices) {
                if(remap[index]<0) {
                    auto inserted=welded.emplace(vertex_key(original[index]),unsigned(bake.vertices.size()));
                    if(inserted.second)bake.vertices.push_back(original[index]);
                    remap[index]=int32_t(inserted.first->second);
                }
                index=remap[index];
            }
        };
        compact(bake.indices);for(auto &lod:bake.lods)compact(lod.indices);
    }
    bake.lod_ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
}
void NativeBlockWorld::set_geometry_lod_enabled(bool enabled) {
    geometry_lod=enabled;
    for(auto &entry:visuals)entry.second.mesh->set_lod_bias(enabled?4.f:1e8f);
}
Dictionary NativeBlockWorld::geometry_lod_stats() const {
    int chunks_with_lods=0,levels=0,base_triangles=0,lowest_triangles=0;int64_t indices_bytes=0;
    for(const auto &entry:visuals) {
        const auto &visual=entry.second;
        base_triangles+=visual.triangles;indices_bytes+=visual.lod_index_bytes;
        lowest_triangles+=visual.lod_min_triangles;levels+=visual.lod_levels;chunks_with_lods+=visual.lod_levels>0;
    }
    Dictionary result;result["enabled"]=geometry_lod;result["chunks_with_lods"]=chunks_with_lods;result["levels"]=levels;
    result["base_triangles"]=base_triangles;result["lowest_triangles"]=lowest_triangles;result["index_bytes"]=indices_bytes;
    result["bake_total_ms"]=lod_bake_total_ms;result["bake_max_ms"]=lod_bake_max_ms;return result;
}
}
