#include "structure_queries.hpp"
#include "block_world.hpp"
#include "static_batch.hpp"
#include "region_world_archive.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
namespace terraforest {
using namespace godot;
void NativeStructureQueries::_bind_methods() {
    ClassDB::bind_method(D_METHOD("capture_models","blocks","models","origin","size"),&NativeStructureQueries::capture_models);
    ClassDB::bind_method(D_METHOD("is_collision_region_ready","blocks","models","world_bounds"),&NativeStructureQueries::is_collision_region_ready);
    ClassDB::bind_method(D_METHOD("overlap_mask","blocks","models","transforms","prototype_bounds"),&NativeStructureQueries::overlap_mask);
    ClassDB::bind_method(D_METHOD("configure_archive","archive","checkpoint"),&NativeStructureQueries::configure_archive);
    ClassDB::bind_method(D_METHOD("clear_exclusion_cache"),&NativeStructureQueries::clear_exclusion_cache);
    ClassDB::bind_method(D_METHOD("exclusion_stats"),&NativeStructureQueries::exclusion_stats);
}
Dictionary NativeStructureQueries::capture_models(NativeBlockWorld *blocks,const Array &models,Vector3i origin,Vector3i size) const {
    Dictionary result;result["ok"]=false;result["reason"]="Invalid capture region or model collection";
    if(!blocks||models.size()>256||size.x<=0||size.y<=0||size.z<=0||size.x>256||size.y>256||size.z>256||int64_t(size.x)*size.y*size.z>262144)return result;
    Transform3D frame=blocks->is_inside_tree()?blocks->get_global_transform():blocks->get_transform();
    if(!frame.is_finite()||std::abs(frame.basis.determinant())<1e-12)return result;
    const AABB region{Vector3(origin),Vector3(size)};
    Array attachments;
    for(int i=0;i<models.size();++i){
        if(models[i].get_type()!=Variant::OBJECT)return result;
        Object *object=models[i];auto *batch=Object::cast_to<NativeStaticBatch>(object);
        if(!batch||batch->source_mesh.is_null())return result;
        if(batch->admission){result["reason"]="Wait for model streaming before capturing";return result;}
        Transform3D model_frame=batch->is_inside_tree()?batch->get_global_transform():batch->get_transform();
        Transform3D relative=frame.affine_inverse()*model_frame;
        if(!relative.is_finite()||std::abs(relative.basis.determinant())<1e-12)return result;
        for(const auto &entry:batch->unloaded_regions)if(relative.xform(entry.second.bounds).intersects(region)){
            result["reason"]="Load all selected model regions before capturing";return result;
        }
        for(const auto &entry:batch->render_bounds){
            if(!relative.xform(entry.second).intersects(region))continue;
            auto group=batch->groups.find(entry.first);if(group==batch->groups.end())continue;
            for(int64_t id:group->second){
                Transform3D pose=relative*batch->placement_transform(batch->placements.at(id));
                AABB bounds=pose.xform(batch->source_mesh->get_aabb());
                if(!bounds.intersects(region))continue;
                if(!region.grow(0.0001).encloses(bounds)){result["reason"]="Expand the selection to include each whole object";return result;}
                if(attachments.size()>=4096){result["reason"]="Capture exceeds 4096 attached objects";return result;}
                pose.origin-=Vector3(origin);
                Dictionary item;item["model"]=batch->asset_id;item["transform"]=pose;attachments.append(item);
            }
        }
    }
    result["ok"]=true;result["reason"]="";result["attachments"]=attachments;return result;
}
bool NativeStructureQueries::is_collision_region_ready(NativeBlockWorld *blocks,const Array &models,const AABB &bounds) const {
    if(!blocks||models.size()>256||!blocks->is_collision_region_ready(bounds))return false;
    for(int i=0;i<models.size();i++) {
        Variant value=models[i];if(value.get_type()!=Variant::OBJECT)return false;
        Object *object=value;auto *model=Object::cast_to<NativeStaticBatch>(object);
        if(!model||!model->is_collision_region_ready(bounds))return false;
    }
    return true;
}
}
