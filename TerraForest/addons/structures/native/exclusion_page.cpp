// SPDX-License-Identifier: 0BSD
#include "exclusion_page.hpp"
#include "static_batch.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
#include <atomic>

namespace terraforest {
static std::atomic<int64_t> exclusion_page_count{0};
ExclusionPageData::ExclusionPageData(){++exclusion_page_count;}
ExclusionPageData::~ExclusionPageData(){--exclusion_page_count;}
int64_t ExclusionPageData::live_pages(){return exclusion_page_count.load();}
void NativeExclusionPage::_bind_methods() {
    ClassDB::bind_method(D_METHOD("load_packet","bytes","expected","asset","region","proxies"),&NativeExclusionPage::load_packet);
    ClassDB::bind_method(D_METHOD("overlaps","bounds"),&NativeExclusionPage::overlaps);
    ClassDB::bind_method(D_METHOD("payload_bytes"),&NativeExclusionPage::payload_bytes);
}
bool ExclusionPageData::load_packet(const PackedByteArray &bytes,const PackedByteArray &expected,const String &asset,Vector3i region,const TypedArray<AABB> &proxies) {
    if(valid||expected.size()!=32||bytes.size()<100||bytes.slice(bytes.size()-32)!=expected||proxies.size()>32)return false;
    BlockKey decoded;
    if(asset.is_empty()) {
        std::map<BlockKey,BlockChunk> chunks;
        if(!proxies.is_empty()||!NativeBlockWorld::parse_region(bytes,decoded,chunks)||Vector3i(decoded.x,decoded.y,decoded.z)!=region)return false;
        columns.reserve(chunks.size());
        for(const auto &entry:chunks)columns.push_back({entry.first,entry.second.columns});
    } else {
        if(proxies.is_empty())return false;
        AABB prototype;
        for(int index=0;index<proxies.size();++index) {
            const AABB part=proxies[index];
            if(!part.position.is_finite()||!part.get_end().is_finite()||part.size.x<0||part.size.y<0||part.size.z<0)return false;
            prototype=index?prototype.merge(part):part;
        }
        std::map<int64_t,NativeStaticBatch::Placement> placements;
        String decoded_asset;
        if(!NativeStaticBatch::parse_region(bytes,decoded_asset,decoded,placements)||decoded_asset!=asset||Vector3i(decoded.x,decoded.y,decoded.z)!=region)return false;
        instances.reserve(placements.size());
        for(const auto &entry:placements) {
            Transform3D transform=NativeStaticBatch::placement_transform(entry.second);
            AABB bounds=transform.xform(prototype);
            if(!bounds.position.is_finite()||!bounds.get_end().is_finite()) {instances.clear();return false;}
            instances.push_back({transform,bounds});
        }
        for(int index=0;index<proxies.size();++index)parts.push_back(proxies[index]);
        branches.reserve(instances.size()/2+1);
        if(!instances.empty())partition(0,uint32_t(instances.size()));
    }
    valid=true;return true;
}
uint32_t ExclusionPageData::partition(uint32_t begin,uint32_t end) {
    const uint32_t index=uint32_t(branches.size());
    Branch branch;branch.begin=begin;branch.end=end;branch.bounds=instances[begin].bounds;
    for(uint32_t item=begin+1;item<end;++item)branch.bounds=branch.bounds.merge(instances[item].bounds);
    branches.push_back(branch);
    if(end-begin>8) {
        const int axis=branch.bounds.size.max_axis_index();
        const uint32_t middle=begin+(end-begin)/2;
        std::nth_element(instances.begin()+begin,instances.begin()+middle,instances.begin()+end,[axis](const Instance &first,const Instance &second){return first.bounds.get_center()[axis]<second.bounds.get_center()[axis];});
        const uint32_t left=partition(begin,middle),right=partition(middle,end);
        branches[index].left=left;branches[index].right=right;
    }
    return index;
}
bool ExclusionPageData::model_overlap(uint32_t index,const AABB &bounds) const {
    const auto &branch=branches[index];
    if(!branch.bounds.intersects(bounds))return false;
    if(branch.left)return model_overlap(branch.left,bounds)||model_overlap(branch.right,bounds);
    for(uint32_t item=branch.begin;item<branch.end;++item) {
        const auto &instance=instances[item];
        if(!instance.bounds.intersects(bounds))continue;
        for(const auto &part:parts)if(instance.transform.xform(part).intersects(bounds))return true;
    }
    return false;
}
bool ExclusionPageData::overlaps(const AABB &bounds) const {
    if(!valid||!bounds.position.is_finite()||!bounds.get_end().is_finite()||bounds.size.x<=0||bounds.size.y<=0||bounds.size.z<=0)return false;
    if(!branches.empty())return model_overlap(0,bounds);
    for(const auto &chunk:columns) {
        const Vector3 origin(chunk.key.x*16,chunk.key.y*16,chunk.key.z*16);
        if(!AABB(origin,Vector3(16,16,16)).intersects(bounds))continue;
        int low[3],high[3];
        bool empty=false;
        for(int axis=0;axis<3;++axis) {
            low[axis]=int(std::floor(std::clamp(double(bounds.position[axis]-origin[axis]),0.0,16.0)));
            high[axis]=int(std::ceil(std::clamp(double(bounds.get_end()[axis]-origin[axis]),0.0,16.0)))-1;
            empty|=low[axis]>high[axis];
        }
        if(empty)continue;
        const uint16_t mask=uint16_t(((1u<<(high[1]+1))-1)&~((1u<<low[1])-1));
        for(int depth=low[2];depth<=high[2];++depth)for(int across=low[0];across<=high[0];++across)
            if(chunk.values[across+16*depth]&mask)return true;
    }
    return false;
}
int64_t ExclusionPageData::payload_bytes() const {
    return sizeof(*this)+columns.capacity()*sizeof(Columns)+instances.capacity()*sizeof(Instance)+parts.capacity()*sizeof(AABB)+branches.capacity()*sizeof(Branch);
}
}
