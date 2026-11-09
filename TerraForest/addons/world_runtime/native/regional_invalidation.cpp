// SPDX-License-Identifier: 0BSD
#include "regional_navigation.hpp"
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
RegionalGraph::Cell RegionalGraph::cell(Vector3 p){
    return {int(std::floor(p.x/8)),int(std::floor(p.y/8)),int(std::floor(p.z/8))};
}
void RegionalGraph::clear(){
    vertices.clear();index.clear();spatial_.clear();free_.clear();requests.clear();
    dependency_extent_=Vector3(4,4,4);lowest=highest=0;++revision;
    invalidation_scanned=invalidation_vertices=invalidation_edges=0;
}
void RegionalGraph::record_dependency(int from,int direction,const AABB &bounds){
    last_dependency=bounds;
    if(from<0)return;
    auto &vertex=vertices[from];const uint8_t bit=uint8_t(1u<<direction);
    vertex.dependencies[direction]=(vertex.dependency_mask&bit)?vertex.dependencies[direction].merge(bounds):bounds;
    vertex.dependency_mask|=bit;
    const auto &region=vertex.dependencies[direction];last_dependency=region;
    // Every certificate is indexed by its source vertex. This monotonic extent
    // bounds even unusually tall sampled stairs; no fixed-height assumption can
    // omit an edge whose actual physics envelope crosses the changed volume.
    const Vector3 a=(region.position-vertex.p).abs(),b=(region.position+region.size-vertex.p).abs();
    for(int axis=0;axis<3;++axis)dependency_extent_[axis]=std::max(dependency_extent_[axis],std::max(a[axis],b[axis])+real_t(.02));
}
bool RegionalGraph::invalidate(const AABB &bounds){
    if(bounds.size==Vector3()||!bounds.position.is_finite()||!bounds.size.is_finite()||
       bounds.size.x<0||bounds.size.y<0||bounds.size.z<0||bounds.position.abs().length()>1000000||
       (bounds.position+bounds.size).abs().length()>1000000){clear();return true;}
    ++revision;invalidation_scanned=invalidation_vertices=invalidation_edges=0;
    const AABB changed=bounds.grow(.001);
    const auto lower=cell(changed.position-dependency_extent_);
    const auto upper=cell(changed.position+changed.size+dependency_extent_);
    const double cells=double(std::get<0>(upper)-std::get<0>(lower)+1)*
        double(std::get<1>(upper)-std::get<1>(lower)+1)*double(std::get<2>(upper)-std::get<2>(lower)+1);
    std::vector<int> candidates;
    if(cells>std::max(size_t(64),spatial_.size()*2)){
        // A broad edit scans the existing bounded index, never millions of
        // empty world cells. This is measured synchronous work, not a deadline.
        for(const auto &entry:spatial_)for(int id:entry.second)candidates.push_back(id);
    }else{
        for(int x=std::get<0>(lower);x<=std::get<0>(upper);++x)
        for(int y=std::get<1>(lower);y<=std::get<1>(upper);++y)
        for(int z=std::get<2>(lower);z<=std::get<2>(upper);++z){
            auto found=spatial_.find({x,y,z});
            if(found!=spatial_.end())for(int id:found->second)candidates.push_back(id);
        }
    }
    invalidation_scanned=candidates.size();
    // Retire affected supports first; incoming edges are invalidated below,
    // before any free slot can be reused. Generation checks protect queries
    // that retain an old slot number across independent local publications.
    for(int id:candidates){
        auto &vertex=vertices[id];const real_t radius=vertex.profile==0?.4:.8;
        if(!AABB(vertex.p-Vector3(radius,1.9,radius),Vector3(radius*2,3.8,radius*2)).intersects(changed))continue;
        auto key=std::make_tuple(vertex.profile,int(std::round(vertex.p.x*2)),int(std::round(vertex.p.z*2)),int(std::round(vertex.p.y*100)));
        auto found=index.find(key);if(found!=index.end()&&found->second==id)index.erase(found);
        auto bucket=spatial_.find(cell(vertex.p));
        if(bucket!=spatial_.end()){bucket->second.erase(id);if(bucket->second.empty())spatial_.erase(bucket);}
        vertex.valid=false;free_.push_back(id);++invalidation_vertices;
    }
    for(int id:candidates){
        auto &vertex=vertices[id];
        for(int direction=0;direction<8;++direction){
            const uint8_t bit=uint8_t(1u<<direction);
            if(!(vertex.dependency_mask&bit))continue;
            const int next=vertex.edge[direction];
            if(vertex.valid&&!vertex.dependencies[direction].intersects(changed)&&
               (next<0||vertices[next].valid))continue;
            vertex.edge[direction]=-2;vertex.progress[direction]=0;vertex.dependency_mask&=~bit;++invalidation_edges;
        }
    }
    return false;
}
}
