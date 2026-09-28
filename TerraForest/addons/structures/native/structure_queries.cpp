#include "structure_queries.hpp"
#include "block_world.hpp"
#include "static_batch.hpp"
#include <godot_cpp/core/class_db.hpp>
namespace terraforest {
using namespace godot;
void NativeStructureQueries::_bind_methods() {
    ClassDB::bind_method(D_METHOD("overlap_mask","blocks","models","transforms","prototype_bounds"),&NativeStructureQueries::overlap_mask);
}
PackedByteArray NativeStructureQueries::overlap_mask(NativeBlockWorld *blocks,const Array &models,const TypedArray<Transform3D> &transforms,const AABB &bounds) const {
    if(!blocks||models.size()>256)return {};
    std::vector<NativeStaticBatch*> collections;
    for(int i=0;i<models.size();i++) {
        Variant value=models[i];if(value.get_type()!=Variant::OBJECT)return {};
        Object *object=value;auto *model=Object::cast_to<NativeStaticBatch>(object);
        if(!model)return {};collections.push_back(model);
    }
    PackedByteArray result=blocks->overlap_mask(transforms,bounds);
    if(result.size()!=transforms.size())return {};
    for(auto *model:collections) {
        PackedByteArray mask=model->overlap_mask(transforms,bounds);
        if(mask.size()!=result.size())return {};
        for(int64_t i=0;i<result.size();i++)result.set(i,result[i]|mask[i]);
    }
    return result;
}
}
