// SPDX-License-Identifier: 0BSD
#pragma once
#include "block_region_store.hpp"
#include "structures_snapshot.hpp"

namespace terraforest {
// An optional native adapter around NativeWorldArchive. One save-worker owner.
// Its sibling .regions directory is exclusively managed by this adapter.
class NativeRegionWorldArchive : public RefCounted {
    GDCLASS(NativeRegionWorldArchive,RefCounted)
    Ref<RefCounted> archive_;
    Ref<NativeStructuresSnapshot> codec_;
    Ref<NativeBlockRegionStore> store_;
    String path_;
    bool reference_in_file(const String &path,std::set<String> &keep) const;
    bool retire_unreferenced();
protected:
    static void _bind_methods();
public:
    ~NativeRegionWorldArchive();
    bool configure(const Ref<RefCounted> &archive,const Ref<NativeStructuresSnapshot> &codec);
    bool acquire(const String &absolute_path);
    void release();
    PackedByteArray encode(const Dictionary &sections) const;
    Dictionary decode(const PackedByteArray &bytes) const;
    PackedByteArray read(const String &absolute_path) const;
    int64_t publish(const String &absolute_path,const PackedByteArray &bytes);
    Dictionary storage_stats() const;
};
}
