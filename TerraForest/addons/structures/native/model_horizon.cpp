// SPDX-License-Identifier: 0BSD
#include "model_horizon.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <algorithm>

namespace terraforest {
void NativeModelHorizon::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","archive","models","checkpoints","byte_limit"),&NativeModelHorizon::configure,DEFVAL(int64_t(128*1024*1024)));
    ClassDB::bind_method(D_METHOD("clear"),&NativeModelHorizon::clear);
    ClassDB::bind_method(D_METHOD("advance","max_records","max_uploads","max_usec"),&NativeModelHorizon::advance,DEFVAL(1024),DEFVAL(2),DEFVAL(1500));
    ClassDB::bind_method(D_METHOD("statistics"),&NativeModelHorizon::statistics);
    ClassDB::bind_method(D_METHOD("represented_ids","collection"),&NativeModelHorizon::represented_ids);
    ClassDB::bind_method(D_METHOD("visual_record","collection","identity"),&NativeModelHorizon::visual_record);
}
NativeStaticBatch *NativeModelHorizon::source(uint64_t identity)const{return Object::cast_to<NativeStaticBatch>(ObjectDB::get_instance(identity));}
MultiMeshInstance3D *NativeModelHorizon::node(uint64_t identity)const{return Object::cast_to<MultiMeshInstance3D>(ObjectDB::get_instance(identity));}
uint64_t NativeModelHorizon::charged_bytes()const{return records*RECORD_CHARGE+pages.size()*PAGE_CHARGE+seeds.size()*SEED_CHARGE+2*READ_CHARGE;}
bool NativeModelHorizon::configure(const Ref<NativeRegionWorldArchive> &reader,const Array &models,const Dictionary &checkpoints,int64_t bytes) {
    if(advancing||!collections.empty()||reader.is_null()||models.size()>256||bytes<16*1024*1024||bytes>256*1024*1024)return false;
    std::map<uint64_t,Collection> staged;size_t regions=0;
    for(int index=0;index<models.size();++index) {
        if(models[index].get_type()!=Variant::OBJECT)return false;
        Object *object=models[index];auto *batch=Object::cast_to<NativeStaticBatch>(object);
        if(!batch||batch->world_render_owner||batch->collision_only||batch->appearance_fade||!batch->render_streaming||batch->source_mesh.is_null()||batch->admission||batch->collection_retirement||staged.count(batch->get_instance_id()))return false;
        Collection entry;entry.id=batch->get_instance_id();entry.epoch=batch->world_render_epoch;
        Variant pin=checkpoints.get(batch->asset_id,PackedByteArray());if(pin.get_type()!=Variant::PACKED_BYTE_ARRAY)return false;
        entry.checkpoint=pin;
        if((!entry.checkpoint.is_empty()&&entry.checkpoint.size()!=32)||(!batch->unloaded_regions.empty()&&entry.checkpoint.size()!=32))return false;
        regions+=batch->groups.size()+batch->unloaded_regions.size();if(regions>65536)return false;
        staged.emplace(entry.id,std::move(entry));
    }
    if(regions*SEED_CHARGE+2*READ_CHARGE>uint64_t(bytes))return false;
    archive=reader;byte_limit=uint64_t(bytes);collections=std::move(staged);error=String();capacity_error=false;
    for(auto &entry:collections) {
        auto *batch=source(entry.first);batch->world_render_owner=get_instance_id();batch->world_render_changes.clear();batch->world_render_seeded.clear();
        while(!batch->batches.empty())batch->release_batch(batch->batches.begin()->first);
        batch->drain_render_retirement(0);for(auto *item:batch->render_pool)memdelete(item);batch->render_pool.clear();
        batch->render_pending.clear();batch->set_process(false);
        if(!seed_collection(entry.second,batch)){clear();return false;}
    }
    set_process(true);return true;
}
bool NativeModelHorizon::seed_collection(Collection &collection,NativeStaticBatch *batch) {
    const size_t count=batch->groups.size()+batch->unloaded_regions.size();
    if(seeds.size()+count>65536||charged_bytes()+count*SEED_CHARGE>byte_limit){capacity_error=false;error="Model visual seed budget exceeded";return false;}
    if(!batch->unloaded_regions.empty()) {
        collection.lease=archive->retain_read_checkpoint(batch->asset_id,collection.checkpoint);
        if(!collection.lease){capacity_error=false;error="Model visual checkpoint is unavailable";return false;}
    }
    collection.epoch=batch->world_render_epoch;
    for(const auto &group:batch->groups) {Seed seed;seed.collection=collection.id;seed.epoch=collection.epoch;seed.region=group.first;seeds.push_back(std::move(seed));}
    for(const auto &group:batch->unloaded_regions) {Seed seed;seed.collection=collection.id;seed.epoch=collection.epoch;seed.region=group.first;seed.checksum=group.second.checksum;seeds.push_back(std::move(seed));}
    collection.seeds=count;return true;
}
void NativeModelHorizon::cancel_seeds(uint64_t identity) {
    for(auto it=seeds.begin();it!=seeds.end();) {
        if(it->collection!=identity){++it;continue;}
        if(it->ticket&&archive.is_valid())archive->discard_survey_region_read(it->ticket);
        if(it->ticket||it->data)--read_slots;
        it=seeds.erase(it);
    }
}
void NativeModelHorizon::remove_page(uint64_t identity) {
    auto found=pages.find(identity);if(found==pages.end())return;
    auto &page=found->second;
    gpu_bytes-=page.gpu_count*48;
    if(auto *instance=node(page.node))memdelete(instance);
    dirty.erase(identity);pages.erase(found);
}
void NativeModelHorizon::discard_collection(Collection &collection) {
    cancel_seeds(collection.id);
    if(collection.lease&&archive.is_valid())archive->release_read_checkpoint(collection.lease);
    collection.lease=0;collection.seeds=0;
    std::vector<uint64_t> remove;for(const auto &page:pages)if(page.second.collection==collection.id)remove.push_back(page.first);
    for(auto identity:remove)remove_page(identity);
    records-=collection.instances.size();rendered-=collection.drawn.size();
    collection.instances.clear();collection.drawn.clear();collection.available.clear();collection.changed_during_seed.clear();
}
void NativeModelHorizon::clear() {
    if(advancing)return;
    for(auto &entry:collections) {
        discard_collection(entry.second);
        if(auto *batch=source(entry.first)) {
            if(batch->world_render_owner==get_instance_id()){batch->world_render_owner=0;batch->world_render_changes.clear();batch->world_render_seeded.clear();batch->render_dirty=true;batch->set_process(batch->render_streaming);}
        }
    }
    collections.clear();archive.unref();set_process(false);gpu_bytes=0;error=String();capacity_error=false;
}
NativeModelHorizon::~NativeModelHorizon(){clear();}
bool NativeModelHorizon::assign(Collection &collection,int64_t identity,const NativeStaticBatch::Placement &transform) {
    auto existing=collection.instances.find(identity);
    if(existing!=collection.instances.end()) {
        auto &page=pages.at(existing->second.page);auto &record=page.records[existing->second.slot];
        if(record.transform!=transform){record.transform=transform;dirty.insert(existing->second.page);}return true;
    }
    const BlockKey origin=NativeStaticBatch::group_for(transform);
    auto candidates=collection.available.find(origin);
    const bool create=candidates==collection.available.end()||candidates->second.empty();
    if(charged_bytes()+RECORD_CHARGE+(create?PAGE_CHARGE:0)>byte_limit||pages.size()+(create?1:0)>16384) {error="Model visual residency budget exceeded";capacity_error=true;return false;}
    uint64_t identity_page;
    if(create) {identity_page=next_page++;DrawPage page;page.collection=collection.id;page.origin=origin;pages.emplace(identity_page,std::move(page));collection.available[origin].insert(identity_page);}
    else identity_page=*candidates->second.begin();
    auto &page=pages.at(identity_page);collection.instances[identity]={identity_page,page.records.size()};page.records.push_back({identity,transform});
    if(page.records.size()==PAGE_CAPACITY)collection.available[origin].erase(identity_page);
    dirty.insert(identity_page);++records;return true;
}
void NativeModelHorizon::erase_drawn(Collection &collection,int64_t identity) {
    auto found=collection.drawn.find(identity);if(found==collection.drawn.end())return;
    auto &page=pages.at(found->second.page);const size_t slot=found->second.slot;
    auto *instance=node(page.node);const auto last=page.drawn.back();
    if(slot+1!=page.drawn.size()) {
        page.drawn[slot]=last;collection.drawn[last.id]={found->second.page,slot};
        if(instance) {Transform3D pose=NativeStaticBatch::placement_transform(last.transform);pose.origin-=Vector3(page.origin.x,page.origin.y,page.origin.z)*32;instance->get_multimesh()->set_instance_transform(int(slot),pose);}
    }
    page.drawn.pop_back();if(instance)instance->get_multimesh()->set_visible_instance_count(int(page.drawn.size()));
    collection.drawn.erase(identity);--rendered;
}
void NativeModelHorizon::erase(Collection &collection,int64_t identity) {
    erase_drawn(collection,identity);
    auto found=collection.instances.find(identity);if(found==collection.instances.end())return;
    const uint64_t key=found->second.page;auto &page=pages.at(key);const size_t slot=found->second.slot;
    const auto last=page.records.back();page.records[slot]=last;collection.instances[last.id]={key,slot};page.records.pop_back();
    collection.instances.erase(identity);--records;
    if(page.records.empty()){collection.available[page.origin].erase(key);remove_page(key);}
    else {collection.available[page.origin].insert(key);dirty.insert(key);}
}
bool NativeModelHorizon::advance_seed(Seed &seed,Collection &collection,NativeStaticBatch *batch) {
    if(seed.data) {
        if(seed.offset==seed.data->records().size())return true;
        const auto &record=seed.data->records()[seed.offset];
        if(!collection.changed_during_seed.count(record.id)&&!assign(collection,record.id,record.transform))return false;
        ++seed.offset;
        ++last_records;return seed.offset==seed.data->records().size();
    }
    if(seed.ticket) {
        std::shared_ptr<ModelRenderPageData> data;
        Dictionary result=archive->take_model_render_read(seed.ticket,data);
        if(result.is_empty())return false;
        seed.ticket=0;
        if(!bool(result.get("ok",false))||!data){--read_slots;error="Model visual checkpoint read failed";return false;}
        seed.data=std::move(data);return false;
    }
    if(batch->admission&&!(batch->admission->key<seed.region)&&!(seed.region<batch->admission->key))return false;
    auto missing=batch->unloaded_regions.find(seed.region);
    if(missing!=batch->unloaded_regions.end()) {
        if(read_slots>=2)return false;
        if(seed.checksum.is_empty())seed.checksum=missing->second.checksum;
        if(seed.checksum!=missing->second.checksum){error="Model visual source changed before bootstrap";return false;}
        seed.ticket=archive->request_model_render_read(batch->asset_id,Vector3i(seed.region.x,seed.region.y,seed.region.z),seed.checksum,collection.checkpoint,int64_t(collection.epoch));
        if(seed.ticket){++reads;++read_slots;}
        else if(!bool(archive->region_read_stats().get("running",false)))error="Model visual archive worker is stopped";
        return false;
    }
    auto group=batch->groups.find(seed.region);if(group==batch->groups.end())return true;
    auto identity=group->second.upper_bound(seed.after);if(identity==group->second.end())return true;
    if(!collection.changed_during_seed.count(*identity)&&!assign(collection,*identity,batch->placements.at(*identity)))return false;
    seed.after=*identity;
    ++last_records;return ++identity==group->second.end();
}
void NativeModelHorizon::refresh_shadow(DrawPage &page) {
    auto *batch=source(page.collection);auto *instance=node(page.node);if(!batch||!instance)return;
    const double radius=batch->shadow_distance>0?batch->shadow_distance:384;
    const auto end=page.bounds.get_end();const Vector3 closest(std::clamp(batch->render_focus.x,page.bounds.position.x,end.x),std::clamp(batch->render_focus.y,page.bounds.position.y,end.y),std::clamp(batch->render_focus.z,page.bounds.position.z,end.z));
    const bool enabled=batch->casts_shadows&&closest.distance_squared_to(batch->render_focus)<=(radius+4)*(radius+4);
    if(page.shadow!=int(enabled)){page.shadow=int(enabled);instance->set_cast_shadows_setting(enabled?GeometryInstance3D::SHADOW_CASTING_SETTING_ON:GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);}
}
bool NativeModelHorizon::upload(uint64_t identity) {
    auto &page=pages.at(identity);auto *batch=source(page.collection);if(!batch)return false;
    auto &collection=collections.at(page.collection);
    PackedFloat32Array buffer;buffer.resize(page.records.size()*12);float *values=buffer.ptrw();AABB bounds;
    const Vector3 origin=Vector3(page.origin.x,page.origin.y,page.origin.z)*32;
    const AABB prototype=batch->source_mesh->get_aabb();
    for(size_t slot=0;slot<page.records.size();++slot) {
        const auto &record=page.records[slot];auto pose=NativeStaticBatch::placement_transform(record.transform);
        const auto box=pose.xform(prototype);bounds=slot?bounds.merge(box):box;
        std::copy(record.transform.begin(),record.transform.end(),values+slot*12);
        values[slot*12+3]-=origin.x;values[slot*12+7]-=origin.y;values[slot*12+11]-=origin.z;
    }
    auto *instance=node(page.node);
    if(!instance){instance=memnew(MultiMeshInstance3D);instance->set_name("WorldModelPage"+String::num_uint64(identity));batch->add_child(instance);page.node=instance->get_instance_id();instance->set_position(origin);}
    Ref<MultiMesh> multi=instance->get_multimesh();
    if(multi.is_null()){multi.instantiate();multi->set_transform_format(MultiMesh::TRANSFORM_3D);instance->set_multimesh(multi);}
    gpu_bytes-=page.gpu_count*48;
    if(multi->get_mesh()!=batch->source_mesh)multi->set_mesh(batch->source_mesh);
    if(multi->get_instance_count()!=int(page.records.size()))multi->set_instance_count(int(page.records.size()));
    multi->set_buffer(buffer);
    if(multi->get_visible_instance_count()!=-1)multi->set_visible_instance_count(-1);
    AABB local=bounds;local.position-=origin;multi->set_custom_aabb(local);page.bounds=bounds;
    page.gpu_count=uint32_t(page.records.size());gpu_bytes+=page.gpu_count*48;uploaded_bytes+=page.gpu_count*48;++uploads;++last_uploads;
    for(const auto &record:page.drawn)collection.drawn.erase(record.id);rendered-=page.drawn.size();page.drawn=page.records;
    for(size_t slot=0;slot<page.drawn.size();++slot)collection.drawn[page.drawn[slot].id]={identity,slot};rendered+=page.drawn.size();
    refresh_shadow(page);return true;
}
void NativeModelHorizon::advance(int64_t max_records,int64_t max_uploads,int64_t max_usec) {
    if(advancing||archive.is_null()||max_records<1||max_records>8192||max_uploads<1||max_uploads>32||max_usec<1||max_usec>10000)return;
    advancing=true;last_records=last_uploads=0;const uint64_t began=Time::get_singleton()->get_ticks_usec();
    if(capacity_error){capacity_error=false;error=String();}
    auto within=[&]{return Time::get_singleton()->get_ticks_usec()-began<uint64_t(max_usec);};
    auto within_records=[&]{return Time::get_singleton()->get_ticks_usec()-began<uint64_t(max_usec)*2/3;};
    for(auto it=collections.begin();it!=collections.end();) {
        auto *batch=source(it->first);auto &collection=it->second;
        if(!batch){discard_collection(collection);it=collections.erase(it);continue;}
        if(collection.epoch!=batch->world_render_epoch){discard_collection(collection);seed_collection(collection,batch);}
        size_t attempts=batch->world_render_changes.size();
        while(attempts--&&!batch->world_render_changes.empty()&&last_records<uint64_t(max_records)&&within_records()&&(error.is_empty()||capacity_error)) {
            auto change=batch->world_render_changes.upper_bound(collection.change_cursor);
            if(change==batch->world_render_changes.end())change=batch->world_render_changes.begin();
            const int64_t identity=*change;collection.change_cursor=identity;++last_records;
            if(collection.seeds)collection.changed_during_seed.insert(identity);
            auto found=batch->placements.find(identity);
            if(found==batch->placements.end())erase(collection,identity);
            else if(!batch->unloaded_regions.count(NativeStaticBatch::group_for(found->second))) {
                if(!assign(collection,identity,found->second))continue;
                if(!collection.seeds)batch->world_render_seeded.insert(NativeStaticBatch::group_for(found->second));
            }
            batch->world_render_changes.erase(identity);
        }
        ++it;
    }
    size_t stalled=0;
    while(!seeds.empty()&&last_records<uint64_t(max_records)&&within_records()&&error.is_empty()) {
        auto &seed=seeds.front();auto found=collections.find(seed.collection);auto *batch=source(seed.collection);
        if(found==collections.end()||!batch)break;
        const auto previous=last_records;
        if(advance_seed(seed,found->second,batch)) {
            if(seed.data)--read_slots;
            batch->world_render_seeded.insert(seed.region);--found->second.seeds;seeds.pop_front();stalled=0;
            if(!found->second.seeds){for(const auto &group:batch->groups)batch->world_render_seeded.insert(group.first);found->second.changed_during_seed.clear();if(found->second.lease)archive->release_read_checkpoint(found->second.lease);found->second.lease=0;}
        } else if(last_records==previous) {
            seeds.push_back(std::move(seeds.front()));seeds.pop_front();if(++stalled>=seeds.size())break;
        } else stalled=0;
    }
    while(!dirty.empty()&&last_uploads<uint64_t(max_uploads)&&within()&&(error.is_empty()||capacity_error)) {
        const auto identity=*dirty.begin();dirty.erase(dirty.begin());upload(identity);
    }
    auto shadow=pages.upper_bound(shadow_cursor);
    for(int count=0;count<128&&shadow!=pages.end()&&within();++count,++shadow){refresh_shadow(shadow->second);shadow_cursor=shadow->first;}
    if(shadow==pages.end())shadow_cursor=0;
    last_usec=Time::get_singleton()->get_ticks_usec()-began;advancing=false;
}
void NativeModelHorizon::_process(double){advance();}
Dictionary NativeModelHorizon::statistics()const {
    uint64_t changes=0;bool current=true;
    for(const auto &entry:collections)if(auto *batch=source(entry.first)){changes+=batch->world_render_changes.size();current=current&&batch->world_render_epoch==entry.second.epoch;}else current=false;
    Dictionary out;out["active"]=archive.is_valid();out["ready"]=archive.is_valid()&&current&&seeds.empty()&&dirty.empty()&&!changes&&error.is_empty();out["error"]=error;
    out["collections"]=int(collections.size());out["records"]=int64_t(records);out["rendered"]=int64_t(rendered);out["pages"]=int64_t(pages.size());out["pending_regions"]=int64_t(seeds.size());out["pending_changes"]=int64_t(changes);out["pending_uploads"]=int64_t(dirty.size());
    out["charged_bytes"]=int64_t(charged_bytes());out["byte_limit"]=int64_t(byte_limit);out["gpu_transform_bytes"]=int64_t(gpu_bytes);out["reads"]=int64_t(reads);out["uploads"]=int64_t(uploads);out["uploaded_bytes"]=int64_t(uploaded_bytes);out["last_records"]=int64_t(last_records);out["last_uploads"]=int64_t(last_uploads);out["last_usec"]=int64_t(last_usec);return out;
}
PackedInt64Array NativeModelHorizon::represented_ids(NativeStaticBatch *batch)const {
    PackedInt64Array ids;if(!batch)return ids;auto found=collections.find(batch->get_instance_id());if(found==collections.end())return ids;
    ids.resize(found->second.drawn.size());int index=0;for(const auto &entry:found->second.drawn)ids.set(index++,entry.first);ids.sort();return ids;
}
Dictionary NativeModelHorizon::visual_record(NativeStaticBatch *batch,int64_t identity)const {
    Dictionary out;if(!batch)return out;auto found=collections.find(batch->get_instance_id());if(found==collections.end())return out;
    auto location=found->second.drawn.find(identity);if(location==found->second.drawn.end())return out;
    const auto &page=pages.at(location->second.page);auto *instance=node(page.node);if(!instance)return out;
    out["node"]=instance;out["slot"]=int64_t(location->second.slot);out["transform"]=NativeStaticBatch::placement_transform(page.drawn[location->second.slot].transform);return out;
}
}
