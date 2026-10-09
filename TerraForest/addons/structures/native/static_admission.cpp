// SPDX-License-Identifier: 0BSD
#include "static_batch.hpp"
#include <chrono>
#include <cstring>
#include <algorithm>

namespace terraforest {
bool NativeStaticBatch::begin_region_admission(const PackedByteArray &bytes) {return begin_region_transfer(bytes,false);}
bool NativeStaticBatch::begin_region_retirement(const PackedByteArray &bytes) {return begin_region_transfer(bytes,true);}
bool NativeStaticBatch::retirement_locks(BlockKey key) const {
    return admission&&admission->retiring&&!(key<admission->key)&&!(admission->key<key);
}
bool NativeStaticBatch::begin_region_transfer(const PackedByteArray &bytes,bool retiring) {
    if(admission||admission_busy||defer_change_signal||admission_ticket==uint64_t(INT64_MAX)||source_mesh.is_null()||
       (!collision_only&&!render_streaming)||bytes.size()<105||bytes.size()>5600232||
       std::memcmp(bytes.ptr(),"TFMR\1\0\0\0",8)||
       std::memcmp(bytes.ptr()+24,"TFSI\1\0\0\0",8)||
       bytes.decode_u32(20)!=uint64_t(bytes.size()-56))return false;
    BlockKey key{int(bytes.decode_s32(8)),int(bytes.decode_s32(12)),int(bytes.decode_s32(16))};
    auto missing=unloaded_regions.find(key);
    const uint64_t length=bytes.decode_u32(32),count=bytes.decode_u32(36);
    if(!valid_model_region(key)||length<1||length>128||count>100000||
       16+length+count*56!=uint64_t(bytes.size()-88))return false;
    if(retiring) {
        auto group=groups.find(key);
        if(missing!=unloaded_regions.end()||count!=(group==groups.end()?0:group->second.size())||
           groups.size()+unloaded_regions.size()+(group==groups.end()?1:0)>4096)return false;
        // Runtime retirement is for cold records. Renderer/proxy owners must
        // release their active resources first; never detach nearby objects.
        auto draw=batches.lower_bound({key,0});
        if(draw!=batches.end()&&!(key<draw->first.first)&&!(draw->first.first<key))return false;
        for(const auto &body:collision_bodies) {
            auto region=group_for(placements.at(body.first));
            if(!(key<region)&&!(region<key))return false;
        }
    } else if(missing==unloaded_regions.end()||groups.count(key)||count!=missing->second.count||
              missing->second.checksum!=bytes.slice(bytes.size()-32))return false;
    for(uint64_t i=0;i<length;++i)if(bytes[40+i]<33||bytes[40+i]>126)return false;
    if(String::utf8(reinterpret_cast<const char*>(bytes.ptr()+40),length)!=asset_id)return false;
    auto staged=std::make_unique<RegionAdmission>();
    staged->retiring=retiring;staged->key=key;staged->packet=bytes;staged->count=count;staged->record_offset=40+length;
    staged->prototype=proxy_parts.empty()?source_mesh->get_aabb():proxy_box;
    staged->mesh_bounds=source_mesh->get_aabb();
    if(!staged->prototype.position.is_finite()||!staged->prototype.get_end().is_finite()||
       !staged->mesh_bounds.position.is_finite()||!staged->mesh_bounds.get_end().is_finite())return false;
    // Reserve once; subsequent per-record steps cannot trigger vector copying.
    if(!retiring)staged->ordered.reserve(count);
    staged->hash.instantiate();staged->hash->start(HashingContext::HASH_SHA256);
    admission_retiring=retiring;if(retiring){render_dirty=true;collision_dirty=true;}
    ++admission_ticket;admission=std::move(staged);admission_result="active";admission_error="";
    admission_step_records=admission_step_bytes=0;return true;
}
void NativeStaticBatch::fail_admission(const String &error) {
    admission->phase=RegionAdmission::ROLLBACK;admission->error=error;
}
bool NativeStaticBatch::admission_owned() {
    if(!admission||!admission->history_owner)return false;
    if(ObjectDB::get_instance(admission->history_owner))return true;
    // Weak owner was destroyed: raw cancellation/advancement is available again.
    admission->history_owner=0;return false;
}
bool NativeStaticBatch::cancel_region_admission() {
    if(!admission||admission->retiring||admission_busy||defer_change_signal||admission_owned())return false;
    fail_admission("cancelled");return true;
}
bool NativeStaticBatch::cancel_region_retirement() {
    if(!admission||!admission->retiring||admission->phase==RegionAdmission::RETIRE_RECORDS||
       admission_busy||defer_change_signal||admission_owned())return false;
    fail_admission("cancelled");return true;
}
Dictionary NativeStaticBatch::advance_region_retirement(int64_t records,int64_t bytes,int64_t usec) {
    if(!admission||!admission->retiring||defer_change_signal||admission_owned())return region_admission_stats();
    return advance_region_admission_impl(records,bytes,usec);
}
Dictionary NativeStaticBatch::region_admission_stats() const {
    Dictionary out;out["ticket"]=int64_t(admission_ticket);out["active"]=bool(admission);out["result"]=admission_result;
    out["error"]=admission?admission->error:admission_error;
    out["operation"]=admission_retiring?"retire":"admit";
    out["staged_records"]=int64_t(admission_retiring?0:hidden_record_count());
    out["retiring_records"]=int64_t(admission_retiring?hidden_record_count():0);
    out["step_records"]=int64_t(admission_step_records);out["step_hash_bytes"]=int64_t(admission_step_bytes);
    out["phase"]=admission?int(admission->phase):-1;return out;
}
Dictionary NativeStaticBatch::advance_region_admission(int64_t max_records,int64_t max_hash_bytes,int64_t max_usec) {
    if((admission&&admission->retiring)||defer_change_signal||admission_owned())return region_admission_stats();
    return advance_region_admission_impl(max_records,max_hash_bytes,max_usec);
}
Dictionary NativeStaticBatch::advance_region_admission_impl(int64_t max_records,int64_t max_hash_bytes,int64_t max_usec) {
    if(admission_busy)return region_admission_stats();
    admission_step_records=admission_step_bytes=0;
    if(!admission||max_records<1||max_records>1024||
       max_hash_bytes<1||max_hash_bytes>262144||max_usec<1||max_usec>2000)return region_admission_stats();
    admission_busy=true;
    const auto deadline=std::chrono::steady_clock::now()+std::chrono::microseconds(max_usec);
    while(admission&&std::chrono::steady_clock::now()<deadline) {
        auto &job=*admission;
        if(job.phase==RegionAdmission::OUTER_HASH||job.phase==RegionAdmission::INNER_HASH) {
            const bool outer=job.phase==RegionAdmission::OUTER_HASH;
            const uint64_t end=job.packet.size()-(outer?32:64);
            if(job.offset<end) {
                if(admission_step_bytes>=uint64_t(max_hash_bytes))break;
                const uint64_t amount=std::min({end-job.offset,uint64_t(max_hash_bytes)-admission_step_bytes,uint64_t(65536)});
                job.hash->update(job.packet.slice(job.offset,job.offset+amount));
                job.offset+=amount;admission_step_bytes+=amount;continue;
            }
            if(job.hash->finish()!=job.packet.slice(end,end+32)) {fail_admission("checksum");continue;}
            if(outer) {job.phase=RegionAdmission::INNER_HASH;job.offset=24;job.hash->start(HashingContext::HASH_SHA256);}
            else {job.phase=RegionAdmission::RECORDS;job.offset=job.record_offset;}
            continue;
        }
        if(job.phase==RegionAdmission::ROLLBACK) {
            if(job.ids.empty()) {
                admission_error=job.error;admission_result=job.error=="cancelled"?"cancelled":"failed";
                if(job.retiring){render_dirty=true;collision_dirty=true;}
                admission.reset();break;
            }
            if(admission_step_records>=uint64_t(max_records))break;
            auto node=job.ids.extract(job.ids.begin());placements.erase(node.value());
            unloaded_ids.insert(std::move(node));++admission_step_records;continue;
        }
        if(job.phase==RegionAdmission::RETIRE_RECORDS) {
            if(job.ids.empty()) {admission.reset();admission_result="complete";break;}
            if(admission_step_records>=uint64_t(max_records))break;
            auto node=job.ids.extract(job.ids.begin());placements.erase(node.value());
            unloaded_ids.insert(std::move(node));++admission_step_records;continue;
        }
        if(job.retiring&&job.validated_records==job.count) {
            const auto key=job.key;
            if(!job.count&&groups.size()+unloaded_regions.size()>=4096) {fail_admission("capacity");continue;}
            UnloadedRegion missing;missing.checksum=job.packet.slice(job.packet.size()-32);missing.count=job.count;
            if(job.count) {
                missing.bounds=collision_bounds.at(key).merge(render_bounds.at(key));
                job.ids=std::move(groups.at(key));groups.erase(key);
                job.ordered=std::move(render_ids.at(key));render_ids.erase(key);
            }
            unloaded_regions.emplace(key,std::move(missing));
            unloaded_bounds.insert(key,unloaded_regions.at(key).bounds);
            collision_bounds.erase(key);render_bounds.erase(key);
            job.phase=RegionAdmission::RETIRE_RECORDS;collision_dirty=true;render_dirty=true;
            // Publish availability before cleanup. Observers/save caches see the
            // whole unavailable disk region, never a prefix of surviving records.
            publish_change();break;
        }
        if(!job.retiring&&job.ids.size()==job.count) {
            // All indexes were prepared a record at a time. Publication moves
            // container ownership, without traversing the dense region again.
            const auto key=job.key;
            if(job.count) {
                groups.emplace(key,std::move(job.ids));render_ids.emplace(key,std::move(job.ordered));
                collision_bounds.emplace(key,job.collision);render_bounds.emplace(key,job.visual);
            }
            unloaded_regions.erase(key);unloaded_bounds.erase(key);collision_dirty=true;render_dirty=true;
            admission.reset();admission_result="complete";
            // Synchronous observers cannot start another admission inside this
            // publication. As with raw restore_region, this is a history barrier.
            publish_change();break;
        }
        if(admission_step_records>=uint64_t(max_records))break;
        const uint8_t *data=job.packet.ptr()+job.offset;
        auto read=[&](int size){uint64_t result=0;for(int i=0;i<size;++i)result|=uint64_t(*data++)<<(8*i);return result;};
        const uint64_t raw=read(8);Placement value;
        for(float &part:value) {uint32_t bits=uint32_t(read(4));std::memcpy(&part,&bits,4);}
        ++admission_step_records;
        if(raw>uint64_t(INT64_MAX)||int64_t(raw)<=job.previous||!valid_transform(value.data())) {fail_admission("record");continue;}
        const int64_t id=int64_t(raw);const auto key=group_for(value);
        if(key<job.key||job.key<key) {fail_admission("identity_or_region");continue;}
        if(job.retiring) {
            auto live=placements.find(id);
            if(live==placements.end()||std::memcmp(live->second.data(),value.data(),sizeof(float)*12)) {fail_admission("stale_record");continue;}
            ++job.validated_records;job.previous=id;job.offset+=56;continue;
        }
        if(placements.count(id)||!unloaded_ids.count(id)) {fail_admission("identity_or_region");continue;}
        const Transform3D transform=placement_transform(value);
        const AABB box=transform.xform(job.prototype),visual=transform.xform(job.mesh_bounds);
        if(!box.position.is_finite()||!box.get_end().is_finite()||!visual.position.is_finite()||!visual.get_end().is_finite()) {fail_admission("bounds");continue;}
        const bool first=job.ids.empty();
        job.collision=first?box:job.collision.merge(box);job.visual=first?visual:job.visual.merge(visual);
        placements.emplace(id,value);job.ids.insert(unloaded_ids.extract(id));job.ordered.push_back(id);
        job.previous=id;job.offset+=56;
    }
    admission_busy=false;return region_admission_stats();
}
}
