// SPDX-License-Identifier: 0BSD
#include "structure_queries.hpp"
#include "static_batch.hpp"
#include <algorithm>
#include <cmath>
#include <vector>

namespace terraforest {
using namespace godot;
Dictionary NativeStructureQueries::nearby_models(const Array &models,Vector3 center,double radius,int limit) const {
    Dictionary result;Array rows;result["objects"]=rows;result["scanned"]=0;result["truncated"]=false;
    if(!center.is_finite()||!std::isfinite(radius)||radius<=0||radius>64||limit<1||limit>256||models.size()>256)return result;
    struct Candidate {NativeStaticBatch *batch;int64_t id;AABB bounds;double distance;};
    std::vector<Candidate> candidates;int scanned=0;bool truncated=false;
    const AABB area(center-Vector3(radius,radius,radius),Vector3(radius*2,radius*2,radius*2));
    for(int index=0;index<models.size();++index){
        if(models[index].get_type()!=Variant::OBJECT)continue;
        Object *object=models[index];auto *batch=Object::cast_to<NativeStaticBatch>(object);
        if(!batch||batch->source_mesh.is_null())continue;
        const Transform3D frame=batch->is_inside_tree()?batch->get_global_transform():batch->get_transform();
        if(!frame.is_finite()||std::abs(frame.basis.determinant())<1e-12)continue;
        const AABB local=frame.affine_inverse().xform(area);
        batch->collision_index.any_intersection(local,[&](BlockKey key){
            auto group=batch->groups.find(key);if(group==batch->groups.end())return false;
            for(int64_t id:group->second){
                if(scanned>=8192){truncated=true;return true;}
                ++scanned;
                if(batch->visual_hidden.count(id))continue;
                auto found=batch->placements.find(id);if(found==batch->placements.end())continue;
                const AABB bounds=(frame*batch->placement_transform(found->second)).xform(batch->source_mesh->get_aabb());
                const double distance=bounds.get_center().distance_squared_to(center);
                if(distance<=radius*radius)candidates.push_back({batch,id,bounds,distance});
            }
            return false;
        });
        if(truncated)break;
    }
    std::sort(candidates.begin(),candidates.end(),[](const Candidate &a,const Candidate &b){
        if(a.distance!=b.distance)return a.distance<b.distance;
        if(a.batch->asset_id!=b.batch->asset_id)return a.batch->asset_id<b.batch->asset_id;
        return a.id<b.id;
    });
    const int count=std::min<int>(limit,candidates.size());
    for(int i=0;i<count;++i){
        const auto &candidate=candidates[i];Dictionary row;
        row["collection"]=candidate.batch;row["asset"]=candidate.batch->asset_id;row["id"]=candidate.id;
        row["bounds"]=candidate.bounds;row["distance"]=std::sqrt(candidate.distance);rows.append(row);
    }
    result["scanned"]=scanned;result["nearby"]=int(candidates.size());result["truncated"]=truncated||int(candidates.size())>limit;
    return result;
}
}
