// SPDX-License-Identifier: 0BSD
#include "static_batch.hpp"
#include <godot_cpp/classes/multi_mesh.hpp>
#include <algorithm>
#include <array>
#include <cmath>

namespace terraforest {
bool NativeStaticBatch::configure_render_partitions(int divisions,double padding) {
    // Opt in before admission. This only changes derived draw membership;
    // canonical placements, 32 m region packets and collision indexes stay exact.
    if((divisions!=1&&divisions!=2&&divisions!=4)||!std::isfinite(padding)||padding<0||padding>1||
       !render_streaming||!appearance_fade||world_render_owner||collection_retirement||admission||
       !placements.empty()||!unloaded_regions.empty()||!batches.empty())return false;
    render_partitions=divisions;render_bounds_padding=padding;render_layout.clear();return true;
}
void NativeStaticBatch::rebuild_render_layout(BlockKey key,bool retain_visible) {
    if(render_partitions==1){render_layout.erase(key);return;}
    auto found=render_ids.find(key);
    if(found==render_ids.end()||found->second.empty()){render_layout.erase(key);return;}
    auto &ids=found->second;
    const int parts=render_partitions,buckets=parts*parts*parts;
    const double span=32.0/parts;
    auto bucket=[&](int64_t id){
        const auto &p=placements.at(id);
        const int x=std::clamp(int(std::floor(p[3]/span))-key.x*parts,0,parts-1);
        const int y=std::clamp(int(std::floor(p[7]/span))-key.y*parts,0,parts-1);
        const int z=std::clamp(int(std::floor(p[11]/span))-key.z*parts,0,parts-1);
        return x+parts*y+parts*parts*z;
    };
    // Linear stable partition. Already visible records precede pending records,
    // so an edit can preserve coverage without admitting extra pending payload.
    std::array<uint64_t,128> counts{},starts{},cursor{};
    std::vector<uint8_t> bin;bin.reserve(ids.size());
    for(auto id:ids){const int index=bucket(id)*2+(retain_visible&&!slots.count(id)?1:0);bin.push_back(uint8_t(index));++counts[index];}
    uint64_t offset=0;
    for(int i=0;i<buckets*2;++i){starts[i]=cursor[i]=offset;offset+=counts[i];}
    std::vector<int64_t> ordered(ids.size());
    for(size_t i=0;i<ids.size();++i)ordered[cursor[bin[i]]++]=ids[i];
    ids.swap(ordered);
    auto &layout=render_layout[key];layout.clear();
    const uint64_t capacity=render_page_capacity();
    for(int bucket_index=0;bucket_index<buckets;++bucket_index){
        const uint64_t visible=counts[bucket_index*2],count=visible+counts[bucket_index*2+1];
        for(uint64_t at=0;at<count;at+=capacity){
            const uint64_t size=std::min(capacity,count-at);
            // Six high bits identify the subcell; low bits hold a bounded page
            // index (the entire collection admits at most 100,000 records).
            const uint32_t page=(uint32_t(bucket_index)<<26)|uint32_t(at/capacity);
            layout.push_back({page,starts[bucket_index*2]+at,size,retain_visible&&at<visible?std::min(size,visible-at):0});
        }
    }
}
NativeStaticBatch::RenderSpan NativeStaticBatch::render_span(RenderKey key) const {
    if(render_partitions==1){
        auto found=render_ids.find(key.first);if(found==render_ids.end())return {key.second,0,0,0};
        const uint64_t first=uint64_t(key.second)*render_page_capacity();
        return {key.second,first,first<found->second.size()?std::min(uint64_t(render_page_capacity()),found->second.size()-first):0,0};
    }
    auto found=render_layout.find(key.first);if(found==render_layout.end())return {key.second,0,0,0};
    const auto &layout=found->second;
    auto it=std::lower_bound(layout.begin(),layout.end(),key.second,[](const RenderSpan &span,uint32_t page){return span.page<page;});
    return it!=layout.end()&&it->page==key.second?*it:RenderSpan{key.second,0,0,0};
}
std::vector<uint32_t> NativeStaticBatch::render_page_keys(BlockKey key) const {
    std::vector<uint32_t> result;
    if(render_partitions==1){
        auto found=render_ids.find(key);if(found==render_ids.end())return result;
        const uint64_t count=(found->second.size()+render_page_capacity()-1)/render_page_capacity();
        result.reserve(count);for(uint32_t page=0;page<count;++page)result.push_back(page);
    }else{
        auto found=render_layout.find(key);if(found==render_layout.end())return result;
        result.reserve(found->second.size());for(const auto &span:found->second)result.push_back(span.page);
    }
    return result;
}
uint32_t NativeStaticBatch::render_page_at(BlockKey key,uint64_t index) const {
    if(render_partitions==1)return uint32_t(index/render_page_capacity());
    const auto &layout=render_layout.at(key);
    auto it=std::upper_bound(layout.begin(),layout.end(),index,[](uint64_t value,const RenderSpan &span){return value<span.start;});
    return it==layout.begin()?layout.front().page:std::prev(it)->page;
}
void NativeStaticBatch::reconcile_partition_pages(const std::set<BlockKey> &keys) {
    std::map<RenderKey,uint64_t> changed;
    for(auto key:keys){
        auto old=batches.lower_bound({key,0});
        for(;old!=batches.end()&&!(key<old->first.first)&&!(old->first.first<key);++old){
            const auto span=render_span(old->first);const auto &before=resident_ids.at(old->first);
            bool same=before.size()==span.retained;
            if(same&&span.retained){const auto &ids=render_ids.at(key);same=std::equal(before.begin(),before.end(),ids.begin()+span.start);}
            if(!same)changed.emplace(old->first,span.retained);
        }
        auto layout=render_layout.find(key);if(layout==render_layout.end())continue;
        for(const auto &span:layout->second)if(span.retained&&!batches.count({key,span.page}))changed.emplace(RenderKey{key,span.page},span.retained);
    }
    // Preserve the set of visible identities atomically within this scene call.
    // No new/pending identities are included. Release all old slots first so a
    // move across two pages cannot erase the destination's newly assigned slot.
    for(const auto &page:changed)release_batch(page.first);
    for(const auto &page:changed)if(page.second)upload_batch(page.first,page.second);
}
void NativeStaticBatch::update_render_bounds(RenderKey key,const Ref<MultiMesh> &multi) {
    if(render_partitions==1&&render_bounds_padding==0){multi->set_custom_aabb(AABB());return;}
    const AABB prototype=source_mesh->get_aabb().grow(render_bounds_padding);
    const Vector3 origin(key.first.x*32,key.first.y*32,key.first.z*32);
    AABB bounds;bool first=true;
    for(auto id:resident_ids.at(key)){
        Transform3D pose=placement_transform(placements.at(id));pose.origin-=origin;
        const AABB next=pose.xform(prototype);bounds=first?next:bounds.merge(next);first=false;
    }
    multi->set_custom_aabb(bounds);
}
}
