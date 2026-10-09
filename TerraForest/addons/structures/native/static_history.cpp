#include "static_history.hpp"
#include <godot_cpp/core/class_db.hpp>

namespace terraforest {
void NativeStaticHistory::_bind_methods() {
    ClassDB::bind_method(D_METHOD("region_has_history","collection","region"),&NativeStaticHistory::region_has_history);
    ClassDB::bind_method(D_METHOD("unload_region","collection","packet"),&NativeStaticHistory::unload_region);
    ClassDB::bind_method(D_METHOD("restore_region","collection","packet"),&NativeStaticHistory::restore_region);
    ClassDB::bind_method(D_METHOD("configure","collections","byte_limit","step_limit"),&NativeStaticHistory::configure);
    ClassDB::bind_method(D_METHOD("clear_history"),&NativeStaticHistory::clear_history);
    ClassDB::bind_method(D_METHOD("insert","collection","transform","protected_bounds"),&NativeStaticHistory::insert,DEFVAL(AABB()));
    ClassDB::bind_method(D_METHOD("erase","collection","id"),&NativeStaticHistory::erase);
    ClassDB::bind_method(D_METHOD("update","collection","id","transform","protected_bounds"),&NativeStaticHistory::update,DEFVAL(AABB()));
    ClassDB::bind_method(D_METHOD("undo","protected_bounds"),&NativeStaticHistory::undo,DEFVAL(AABB()));
    ClassDB::bind_method(D_METHOD("redo","protected_bounds"),&NativeStaticHistory::redo,DEFVAL(AABB()));
    ClassDB::bind_method(D_METHOD("stats"),&NativeStaticHistory::stats);
}
NativeStaticBatch *NativeStaticHistory::resolve(uint64_t id) {
    return Object::cast_to<NativeStaticBatch>(ObjectDB::get_instance(id));
}
bool NativeStaticHistory::registered(NativeStaticBatch *collection) const {
    return collection&&revisions.count(collection->get_instance_id());
}
void NativeStaticHistory::clear_records() {
    decltype(undo_edits)().swap(undo_edits);decltype(redo_edits)().swap(redo_edits);
}
bool NativeStaticHistory::synchronize() {
    bool intact=true;
    for(auto it=revisions.begin();it!=revisions.end();) {
        auto *collection=resolve(it->first);
        if(!collection){intact=false;it=revisions.erase(it);continue;}
        if(it->second!=collection->edit_revision){intact=false;it->second=collection->edit_revision;}
        ++it;
    }
    if(!intact){if(!undo_edits.empty()||!redo_edits.empty())++barriers;clear_records();}
    return intact;
}
bool NativeStaticHistory::configure(const Array &collections,int64_t bytes,int64_t steps) {
    if(busy||collections.size()>256||bytes<0||bytes>64*1024*1024||steps<0||steps>1024)return false;
    std::map<uint64_t,uint64_t> staged;
    for(int i=0;i<collections.size();++i) {
        Variant value=collections[i];if(value.get_type()!=Variant::OBJECT)return false;
        Object *object=value;auto *collection=Object::cast_to<NativeStaticBatch>(object);
        if(!collection||!staged.emplace(collection->get_instance_id(),collection->edit_revision).second)return false;
    }
    revisions=std::move(staged);byte_limit=uint64_t(bytes);step_limit=int(steps);clear_records();return true;
}
bool NativeStaticHistory::clear_history() {
    if(busy)return false;synchronize();clear_records();return true;
}
PackedFloat32Array NativeStaticHistory::packed(const NativeStaticBatch::Placement &value) {
    PackedFloat32Array result;result.resize(12);std::copy(value.begin(),value.end(),result.ptrw());return result;
}
void NativeStaticHistory::remember(const Edit &edit) {
    decltype(redo_edits)().swap(redo_edits);
    if(!step_limit||byte_limit<sizeof(Edit)) {clear_records();++unrecorded;return;}
    undo_edits.push_back(edit);
    while(undo_edits.size()>size_t(step_limit)||undo_edits.size()*sizeof(Edit)>byte_limit)undo_edits.pop_front();
}
void NativeStaticHistory::publish(NativeStaticBatch *collection) {
    // Update cursor/revision before notifying observers. Reject reentrant history
    // commands until callbacks finish; external batch mutations form a barrier.
    revisions[collection->get_instance_id()]=collection->edit_revision;
    collection->defer_change_signal=false;
    collection->emit_signal("changed");
    busy=false;
    synchronize(); // A callback may mutate or destroy any registered collection.
}
int64_t NativeStaticHistory::insert(NativeStaticBatch *collection,const PackedFloat32Array &transform,const AABB &protection) {
    if(busy)return 0;synchronize();
    if(!registered(collection)||!collection->can_insert_instance(transform,protection))return 0;
    Edit edit;edit.collection=collection->get_instance_id();edit.has_after=true;
    std::copy(transform.ptr(),transform.ptr()+12,edit.after.begin());
    busy=true;collection->defer_change_signal=true;
    edit.id=collection->insert_instance(transform,protection);
    if(!edit.id){collection->defer_change_signal=false;busy=false;return 0;}
    remember(edit);publish(collection);return edit.id;
}
bool NativeStaticHistory::erase(NativeStaticBatch *collection,int64_t id) {
    if(busy)return false;synchronize();
    if(!registered(collection))return false;
    auto found=collection->placements.find(id);if(found==collection->placements.end())return false;
    Edit edit;edit.collection=collection->get_instance_id();edit.id=id;edit.had_before=true;edit.before=found->second;
    PackedInt64Array ids;ids.push_back(id);
    busy=true;collection->defer_change_signal=true;
    bool ok=collection->remove_instances(ids);
    if(!ok){collection->defer_change_signal=false;busy=false;return false;}
    remember(edit);publish(collection);return true;
}
bool NativeStaticHistory::update(NativeStaticBatch *collection,int64_t id,const PackedFloat32Array &transform,const AABB &protection) {
    if(busy)return false;synchronize();
    if(!registered(collection)||!collection->placement_clear(transform,protection))return false;
    auto found=collection->placements.find(id);if(found==collection->placements.end())return false;
    Edit edit;edit.collection=collection->get_instance_id();edit.id=id;edit.had_before=edit.has_after=true;edit.before=found->second;
    std::copy(transform.ptr(),transform.ptr()+12,edit.after.begin());
    if(edit.before==edit.after)return true;
    PackedInt64Array ids;ids.push_back(id);
    busy=true;collection->defer_change_signal=true;
    bool ok=collection->upsert_instances(ids,transform);
    if(!ok){collection->defer_change_signal=false;busy=false;return false;}
    remember(edit);publish(collection);return true;
}
bool NativeStaticHistory::replay(bool backwards,const AABB &protection) {
    if(busy||!synchronize())return false;
    auto &source=backwards?undo_edits:redo_edits;
    auto &destination=backwards?redo_edits:undo_edits;
    if(source.empty()||!protection.position.is_finite()||!protection.size.is_finite()||
       protection.size.x<0||protection.size.y<0||protection.size.z<0)return false;
    Edit edit=source.back();auto *collection=resolve(edit.collection);if(!collection)return false;
    bool exists=backwards?edit.had_before:edit.has_after;
    const auto &value=backwards?edit.before:edit.after;
    auto transform=packed(value);
    if(exists&&!collection->placement_clear(transform,protection))return false;
    PackedInt64Array ids;ids.push_back(edit.id);
    busy=true;collection->defer_change_signal=true;
    bool ok=exists?collection->upsert_instances(ids,transform):collection->remove_instances(ids);
    if(!ok){collection->defer_change_signal=false;busy=false;return false;}
    destination.push_back(edit);source.pop_back();publish(collection);return true;
}
Dictionary NativeStaticHistory::stats() {
    if(!busy)synchronize();
    Dictionary out;out["undo_steps"]=int(undo_edits.size());out["redo_steps"]=int(redo_edits.size());
    out["record_bytes"]=int64_t((undo_edits.size()+redo_edits.size())*sizeof(Edit));out["record_size"]=int(sizeof(Edit));
    out["byte_limit"]=int64_t(byte_limit);out["step_limit"]=step_limit;out["collections"]=int(revisions.size());
    out["barriers"]=int64_t(barriers);out["unrecorded_edits"]=int64_t(unrecorded);out["busy"]=busy;return out;
}
bool NativeStaticHistory::region_referenced(uint64_t collection,BlockKey region) const {
    auto matches=[&](const NativeStaticBatch::Placement &placement){auto key=NativeStaticBatch::group_for(placement);return !(key<region)&&!(region<key);};
    for(const auto *edits:{&undo_edits,&redo_edits})for(const auto &edit:*edits)
        if(edit.collection==collection&&((edit.had_before&&matches(edit.before))||(edit.has_after&&matches(edit.after))))return true;
    return false;
}
bool NativeStaticHistory::region_has_history(NativeStaticBatch *collection,Vector3i region) {
    if(busy)return true;synchronize();
    BlockKey key{region.x,region.y,region.z};
    return !registered(collection)||!NativeStaticBatch::valid_model_region(key)||region_referenced(collection->get_instance_id(),key);
}
bool NativeStaticHistory::transfer_region(NativeStaticBatch *collection,const PackedByteArray &packet,bool restore) {
    if(busy)return false;synchronize();
    if(!registered(collection))return false;
    String asset;BlockKey region;std::map<int64_t,NativeStaticBatch::Placement> values;
    if(!NativeStaticBatch::parse_region(packet,asset,region,values)||asset!=collection->asset_id||region_referenced(collection->get_instance_id(),region))return false;
    busy=true;collection->defer_change_signal=true;
    bool ok=restore?collection->restore_region_impl(packet):collection->unload_region_impl(packet);
    if(!ok){collection->defer_change_signal=false;busy=false;return false;}
    // This is a residency transition, not an authored edit. Keep both journal
    // stacks and publish the revision through the same reentrancy-safe path.
    publish(collection);return true;
}
}
