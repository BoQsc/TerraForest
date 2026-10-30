// SPDX-License-Identifier: 0BSD
#include "structure_queries.hpp"
#include "exclusion_page.hpp"
#include "static_batch.hpp"
#include "model_transfer_scheduler.hpp"
#include <godot_cpp/classes/time.hpp>
#include <algorithm>
#include <cmath>

namespace terraforest {
struct StructureExclusionCache {
    static constexpr uint64_t LIMIT=32*1024*1024,ENTRY_BYTES=4096;
    using Key=std::tuple<uint64_t,uint64_t,BlockKey,String>;
    struct Entry {
        Ref<NativeRegionWorldArchive> archive;
        std::shared_ptr<ExclusionPageData> page;
        TypedArray<AABB> parts;
        int64_t ticket=0;
        uint64_t bytes=0,used=0,retry=0;
    };
    std::map<Key,Entry> pages;
    Ref<NativeRegionWorldArchive> block_archive;
    PackedByteArray block_checkpoint;
    uint64_t serial=0,bytes=0,high_bytes=0,reads=0,hits=0,failures=0,evictions=0,last_us=0;
    int pending=0;
    String state="ready";
    ~StructureExclusionCache(){clear();}
    void clear() {
        for(auto &entry:pages)if(entry.second.ticket)entry.second.archive->discard_survey_region_read(entry.second.ticket);
        pages.clear();bytes=0;pending=0;state="ready";
    }
    void poll() {
        ++serial;state="ready";
        for(auto &record:pages) {
            auto &entry=record.second;
            if(!entry.ticket)continue;
            std::shared_ptr<ExclusionPageData> page;
            Dictionary reply=entry.archive->take_exclusion_read(entry.ticket,page);
            if(reply.is_empty())continue;
            const uint64_t reservation=entry.bytes-ENTRY_BYTES;
            entry.ticket=0;--pending;bytes-=entry.bytes;entry.bytes=ENTRY_BYTES;
            if(bool(reply.get("ok",false))) {
                if(page&&uint64_t(page->payload_bytes())<=reservation) {
                    entry.page=page;entry.bytes+=page->payload_bytes();
                }
            }
            if(!entry.page){++failures;entry.retry=Time::get_singleton()->get_ticks_msec()+1000;}
            bytes+=entry.bytes;high_bytes=std::max(high_bytes,bytes);
        }
    }
    std::shared_ptr<ExclusionPageData> get(uint64_t owner,const Ref<NativeRegionWorldArchive> &archive,const String &asset,BlockKey region,const PackedByteArray &digest,const PackedByteArray &checkpoint,const TypedArray<AABB> &parts) {
        if(archive.is_null()){state="unavailable";return {};}
        const Key key{owner,uint64_t(archive->get_instance_id()),region,digest.hex_encode()};
        auto found=pages.find(key);
        if(found!=pages.end()&&found->second.parts!=parts) {
            if(found->second.ticket){found->second.archive->discard_survey_region_read(found->second.ticket);--pending;}
            bytes-=found->second.bytes;pages.erase(found);found=pages.end();
        }
        if(found!=pages.end()) {
            auto &entry=found->second;entry.used=serial;
            if(entry.page){++hits;return entry.page;}
            if(entry.ticket){if(state=="ready")state="pending";return {};}
            if(entry.retry>Time::get_singleton()->get_ticks_msec()){state="unavailable";return {};}
            bytes-=entry.bytes;pages.erase(found);
        }
        if(pending>=2){if(state=="ready")state="pending";return {};}
        const uint64_t reservation=(asset.is_empty()?36*1024:12*1024*1024)+ENTRY_BYTES;
        while(bytes+reservation>LIMIT||pages.size()>=256) {
            auto oldest=pages.end();
            for(auto candidate=pages.begin();candidate!=pages.end();++candidate)
                if(!candidate->second.ticket&&candidate->second.used!=serial&&(oldest==pages.end()||candidate->second.used<oldest->second.used))oldest=candidate;
            if(oldest==pages.end()){state="budget";return {};}
            bytes-=oldest->second.bytes;pages.erase(oldest);++evictions;
        }
        const int64_t ticket=archive->request_exclusion_read(asset,Vector3i(region.x,region.y,region.z),digest,checkpoint,int64_t(serial),parts);
        if(!ticket){
            if(!bool(archive->region_read_stats()["running"]))state="unavailable";
            else if(state=="ready")state="pending";
            return {};
        }
        Entry entry;entry.archive=archive;entry.parts=parts.duplicate();entry.ticket=ticket;entry.bytes=reservation;entry.used=serial;
        pages.emplace(key,std::move(entry));bytes+=reservation;++pending;++reads;high_bytes=std::max(high_bytes,bytes);
        if(state=="ready")state="pending";return {};
    }
};
NativeStructureQueries::NativeStructureQueries():exclusion(std::make_unique<StructureExclusionCache>()){}
NativeStructureQueries::~NativeStructureQueries()=default;
void NativeStructureQueries::clear_exclusion_cache(){exclusion->clear();}
void NativeStructureQueries::configure_archive(const Ref<NativeRegionWorldArchive> &archive,const PackedByteArray &checkpoint) {
    if(exclusion->block_archive!=archive)exclusion->clear();
    exclusion->block_archive=archive;exclusion->block_checkpoint=checkpoint;
}
Dictionary NativeStructureQueries::exclusion_stats() const {
    Dictionary result;
    result["state"]=exclusion->state;result["pages"]=int64_t(exclusion->pages.size());result["pending"]=exclusion->pending;
    result["bytes"]=int64_t(exclusion->bytes);result["byte_limit"]=int64_t(StructureExclusionCache::LIMIT);result["high_bytes"]=int64_t(exclusion->high_bytes);
    result["reads"]=int64_t(exclusion->reads);result["hits"]=int64_t(exclusion->hits);result["failures"]=int64_t(exclusion->failures);
    result["evictions"]=int64_t(exclusion->evictions);result["last_us"]=int64_t(exclusion->last_us);
    result["live_pages"]=NativeExclusionPage::live_pages();return result;
}
PackedByteArray NativeStructureQueries::overlap_mask(NativeBlockWorld *blocks,const Array &models,const TypedArray<Transform3D> &transforms,const AABB &bounds) {
    const uint64_t begin=Time::get_singleton()->get_ticks_usec();
    exclusion->poll();exclusion->state="invalid";
    if(!blocks||models.size()>256)return {};
    std::vector<NativeStaticBatch*> collections;
    for(int index=0;index<models.size();++index) {
        Variant value=models[index];if(value.get_type()!=Variant::OBJECT)return {};
        Object *object=value;auto *model=Object::cast_to<NativeStaticBatch>(object);
        if(!model)return {};collections.push_back(model);
    }
    PackedByteArray result=blocks->overlap_mask_impl(transforms,bounds,false);
    if(result.size()!=transforms.size())return {};
    for(auto *model:collections) {
        PackedByteArray mask=model->overlap_mask_impl(transforms,bounds,false);
        if(mask.size()!=result.size())return {};
        for(int64_t index=0;index<result.size();++index)result.set(index,result[index]|mask[index]);
    }
    exclusion->state="ready";
    if(transforms.is_empty()){exclusion->last_us=Time::get_singleton()->get_ticks_usec()-begin;return result;}
    const Transform3D block_inverse=(blocks->is_inside_tree()?blocks->get_global_transform():blocks->get_transform()).affine_inverse();
    std::vector<AABB> block_queries;block_queries.reserve(transforms.size());
    std::map<BlockKey,std::vector<int>> block_regions;
    for(int index=0;index<transforms.size();++index) {
        const Transform3D pose=transforms[index];const AABB box=(block_inverse*pose).xform(bounds);block_queries.push_back(box);
        if(result[index]||blocks->unloaded_regions.empty())continue;
        const Vector3 low=box.position.max(Vector3(-1048576,-1048576,-1048576)),high=box.get_end().min(Vector3(1048576,1048576,1048576));
        if(low.x>=high.x||low.y>=high.y||low.z>=high.z)continue;
        const BlockKey first{int(std::floor(low.x/64)),int(std::floor(low.y/64)),int(std::floor(low.z/64))};
        const BlockKey last{int(std::ceil(high.x/64))-1,int(std::ceil(high.y/64))-1,int(std::ceil(high.z/64))-1};
        const int64_t volume=int64_t(last.x-first.x+1)*(last.y-first.y+1)*(last.z-first.z+1);
        if(volume<=int64_t(blocks->unloaded_regions.size())) {
            for(int depth=first.z;depth<=last.z;++depth)for(int height=first.y;height<=last.y;++height)for(int across=first.x;across<=last.x;++across) {
                const BlockKey key{across,height,depth};if(blocks->unloaded_regions.count(key))block_regions[key].push_back(index);
            }
        } else for(const auto &entry:blocks->unloaded_regions)
            if(AABB(Vector3(entry.first.x*64,entry.first.y*64,entry.first.z*64),Vector3(64,64,64)).intersects(box))block_regions[entry.first].push_back(index);
    }
    bool ready=true;
    for(const auto &entry:block_regions) {
        auto page=exclusion->get(blocks->get_instance_id(),exclusion->block_archive,String(),entry.first,blocks->unloaded_regions.at(entry.first),exclusion->block_checkpoint,{});
        if(!page){ready=false;continue;}
        for(int index:entry.second)if(!result[index]&&page->overlaps(block_queries[index]))result.set(index,1);
    }
    for(auto *model:collections) {
        if(model->unloaded_regions.empty()||model->source_mesh.is_null()||transforms.is_empty())continue;
        const Transform3D inverse=(model->is_inside_tree()?model->get_global_transform():model->get_transform()).affine_inverse();
        std::vector<AABB> queries;queries.reserve(transforms.size());AABB combined;
        for(int index=0;index<transforms.size();++index) {
            const Transform3D pose=transforms[index];const AABB box=(inverse*pose).xform(bounds);
            queries.push_back(box);combined=index?combined.merge(box):box;
        }
        TypedArray<AABB> parts;
        if(model->proxy_parts.empty())parts.push_back(model->source_mesh->get_aabb());
        else for(const auto &part:model->proxy_parts)parts.push_back(part);
        const auto visit=[&](const auto &self,const ModelBoundsIndex::Node *node)->void {
            if(!node||!node->bounds.intersects(combined))return;
            if(node->box.intersects(combined)&&model->unloaded_regions.at(node->key).count) {
                std::vector<int> candidates;
                for(int index=0;index<transforms.size();++index)if(!result[index]&&node->box.intersects(queries[index]))candidates.push_back(index);
                if(!candidates.empty()) {
                    auto lease=model->paging_checkpoint;
                    auto page=exclusion->get(model->get_instance_id(),lease?lease->archive:Ref<NativeRegionWorldArchive>(),model->asset_id,node->key,model->unloaded_regions.at(node->key).checksum,lease?lease->checkpoint:PackedByteArray(),parts);
                    if(!page)ready=false;
                    else for(int index:candidates)if(page->overlaps(queries[index]))result.set(index,1);
                }
            }
            self(self,node->left.get());self(self,node->right.get());
        };
        visit(visit,model->unloaded_bounds.root());
    }
    exclusion->last_us=Time::get_singleton()->get_ticks_usec()-begin;
    if(!ready)return {};
    exclusion->state="ready";return result;
}
}
