#pragma once
#include "block_world.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <mutex>

namespace terraforest {
// Synchronous native storage, intended for one I/O owner/worker. No scene nodes.
class NativeBlockRegionStore : public RefCounted {
    GDCLASS(NativeBlockRegionStore,RefCounted)
    using Digest=std::array<uint8_t,32>;
    struct Entry { Digest digest{}; uint32_t size=0; };
    using Catalog=std::map<BlockKey,Entry>;
    struct Checkpoint {Catalog entries;uint64_t generation=0;};
    mutable std::mutex mutex_;
    void *lease_=nullptr,*scan_=nullptr;
    String directory_;
    Catalog entries_;
    std::set<Digest> retained_;
    std::map<Digest,Checkpoint> checkpoints_;
    std::map<Digest,uint32_t> pinned_blobs_;
    PackedByteArray pins_bytes_;
    PackedByteArray canonical_bytes_,backup_bytes_;
    bool canonical_exists_=false,backup_exists_=false,canonical_active_=false,backup_valid_=false,recovered_=false;
    uint64_t generation_=0,generation_floor_=0,deleted_=0;
    static bool packet_entry(const PackedByteArray &bytes,BlockKey &key,Entry &entry);
    static bool parse_catalog(const PackedByteArray &bytes,Catalog &entries,uint64_t &generation);
    static PackedByteArray encode_catalog(const Catalog &entries,uint64_t generation);
    static PackedByteArray pack_digest(const Digest &digest);
    bool observed_files_unchanged() const;
    bool open_checkpoints(bool allow_initialize);
    bool publish_pins(const std::set<Digest> &ids);
    Dictionary read_entry(const BlockKey &key,const Entry &entry,uint64_t generation) const;
    void reset_scan();
    void rebuild_retained();
    void close_locked();
    Dictionary commit_catalog(Catalog &&next);
protected:
    static void _bind_methods();
public:
    ~NativeBlockRegionStore();
    Dictionary open_store(const String &absolute_directory,bool recover_backup=false);
    void close();
    Dictionary stats() const;
    PackedInt32Array list_regions() const;
    PackedByteArray checksum(Vector3i region) const;
    Dictionary read_region(Vector3i region) const;
    Dictionary publish_region(const PackedByteArray &packet,const PackedByteArray &expected_checksum);
    Dictionary publish_regions(const Array &packets,const Array &expected_checksums);
    Dictionary remove_region(Vector3i region,const PackedByteArray &expected_checksum);
    Dictionary collect_garbage(int max_inspected);
    Dictionary pin_checkpoint();
    PackedByteArray list_checkpoints() const;
    Dictionary checkpoint_regions(const PackedByteArray &checkpoint) const;
    Dictionary read_checkpoint_region(const PackedByteArray &checkpoint,Vector3i region) const;
    Dictionary activate_checkpoint(const PackedByteArray &checkpoint);
    Dictionary release_checkpoint(const PackedByteArray &checkpoint);
    Dictionary publish_block_snapshot(const PackedByteArray &blocks);
    Dictionary publish_storage_state(const PackedByteArray &resident,const PackedInt32Array &unavailable_keys,const PackedByteArray &unavailable_checksums);
    Dictionary read_block_checkpoint(const PackedByteArray &checkpoint) const;
};
}
