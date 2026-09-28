#include "static_batch.hpp"
#include <cmath>

namespace terraforest {
PackedByteArray NativeStaticBatch::overlap_mask(const TypedArray<Transform3D> &transforms,const AABB &bounds) const {
    PackedByteArray result;
    if(transforms.size()>65536||!bounds.position.is_finite()||!bounds.size.is_finite()||
       bounds.size.x<=0||bounds.size.y<=0||bounds.size.z<=0)return result;
    Transform3D frame=is_inside_tree()?get_global_transform():get_transform();
    double determinant=frame.basis.determinant();
    if(!frame.is_finite()||!std::isfinite(determinant)||std::abs(determinant)<1e-12)return result;
    Transform3D inverse=frame.affine_inverse();
    std::vector<AABB> queries;queries.reserve(transforms.size());
    AABB combined;
    for(int64_t i=0;i<transforms.size();i++) {
        Transform3D t=transforms[i];double det=t.basis.determinant();
        if(!t.is_finite()||!std::isfinite(det)||std::abs(det)<1e-12)return PackedByteArray();
        AABB box=(inverse*t).xform(bounds);
        if(!box.position.is_finite()||!box.get_end().is_finite())return PackedByteArray();
        queries.push_back(box);combined=i?combined.merge(box):box;
    }
    result.resize(transforms.size());result.fill(0);
    if(queries.empty()||source_mesh.is_null())return result;
    const AABB fallback=proxy_parts.empty()?source_mesh->get_aabb():AABB();
    // Test group bounds once per batch before traversing nearby authored records.
    // This index is independent of physics residency and retains compound gaps.
    for(const auto &entry:collision_bounds) {
        if(!entry.second.intersects(combined))continue;
        std::vector<int> candidates;
        for(size_t i=0;i<queries.size();i++)if(!result[i]&&entry.second.intersects(queries[i]))candidates.push_back(int(i));
        if(candidates.empty())continue;
        for(auto id:groups.at(entry.first)) {
            Transform3D placement=placement_transform(placements.at(id));
            int count=proxy_parts.empty()?1:int(proxy_parts.size());
            for(int part=0;part<count;part++) {
                AABB solid=placement.xform(proxy_parts.empty()?fallback:proxy_parts[part]);
                for(size_t i=0;i<candidates.size();) {
                    if(solid.intersects(queries[candidates[i]])) {
                        result.set(candidates[i],1);candidates[i]=candidates.back();candidates.pop_back();
                    } else ++i;
                }
                if(candidates.empty())break;
            }
            if(candidates.empty())break;
        }
    }
    return result;
}
}
