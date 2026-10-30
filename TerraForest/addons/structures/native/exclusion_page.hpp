// SPDX-License-Identifier: 0BSD
#pragma once
#include "block_world.hpp"
#include <memory>

namespace terraforest {
class ExclusionPageData {
    struct Columns {BlockKey key;std::array<uint16_t,256> values;};
    struct Instance {Transform3D transform;AABB bounds;};
    struct Branch {AABB bounds;uint32_t begin=0,end=0,left=0,right=0;};
    std::vector<Columns> columns;
    std::vector<Instance> instances;
    std::vector<AABB> parts;
    std::vector<Branch> branches;
    bool valid=false;
    uint32_t partition(uint32_t begin,uint32_t end);
    bool model_overlap(uint32_t branch,const AABB &bounds) const;
public:
    ExclusionPageData();
    ~ExclusionPageData();
    static int64_t live_pages();
    bool load_packet(const PackedByteArray &bytes,const PackedByteArray &expected,const String &asset,Vector3i region,const TypedArray<AABB> &proxies);
    bool overlaps(const AABB &bounds) const;
    int64_t payload_bytes() const;
};
class NativeExclusionPage : public RefCounted {
    GDCLASS(NativeExclusionPage,RefCounted)
    std::shared_ptr<ExclusionPageData> data=std::make_shared<ExclusionPageData>();
protected:
    static void _bind_methods();
public:
    static int64_t live_pages(){return ExclusionPageData::live_pages();}
    bool load_packet(const PackedByteArray &bytes,const PackedByteArray &expected,const String &asset,Vector3i region,const TypedArray<AABB> &proxies){return data->load_packet(bytes,expected,asset,region,proxies);}
    bool overlaps(const AABB &bounds) const{return data->overlaps(bounds);}
    int64_t payload_bytes() const{return data->payload_bytes();}
};
}
