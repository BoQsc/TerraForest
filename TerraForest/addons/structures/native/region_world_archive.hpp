// SPDX-License-Identifier: 0BSD
#pragma once
#include "block_region_store.hpp"
#include "structures_snapshot.hpp"
#include "model_region_store.hpp"
#include <condition_variable>
#include <deque>
#include <thread>

namespace terraforest {
// An optional native adapter around NativeWorldArchive. One save-worker owner.
// Its sibling .regions directory is exclusively managed by this adapter.
class NativeRegionWorldArchive : public RefCounted {
    GDCLASS(NativeRegionWorldArchive,RefCounted)
    Ref<RefCounted> archive_;
    Ref<NativeStructuresSnapshot> codec_;
    Ref<NativeBlockRegionStore> store_;
    String path_;
    mutable std::map<String,Ref<NativeModelRegionStore>> model_stores_;
    mutable std::mutex model_mutex_;
    Ref<NativeModelRegionStore> model_store(const String &asset,bool create) const;
    bool model_references_in_file(const String &path,std::map<String,std::set<String>> &keep) const;
    bool metadata_first_=false;
    int64_t published_index_revision_=0;
    PackedInt32Array published_keys_;
    PackedByteArray published_checksums_,published_checkpoint_;
    struct RegionRead {
        int64_t ticket=0,epoch=0;
        String asset;
        bool metadata=false,strict_checkpoint=false;
        Vector3i region;
        PackedByteArray expected,checkpoint;
    };
    mutable std::mutex read_mutex_;
    using ReadCheckpointKey = std::pair<String,String>; // asset (empty for blocks), hex digest
    std::map<ReadCheckpointKey,uint32_t> read_checkpoint_refs_;
    std::map<int64_t,ReadCheckpointKey> read_checkpoint_leases_;
    int read_checkpoint_lease_limit_=1024;
    int64_t read_next_lease_=1,read_checkpoint_busy_rejections_=0;
    bool checkpoint_sweep_active_=false;
    void release_checkpoint_ref_locked(const ReadCheckpointKey &key);
    std::condition_variable read_wake_;
    std::thread read_worker_;
    std::deque<RegionRead> read_pending_;
    std::deque<Dictionary> read_completed_;
    std::deque<Dictionary> model_read_completed_;
    bool read_running_=false,read_stopping_=false,read_active_=false;
    int read_request_limit_=0,read_outstanding_=0,read_high_requests_=0;
    int64_t read_byte_limit_=0,read_reserved_=0,read_high_bytes_=0,read_next_ticket_=1;
    int64_t read_accepted_=0,read_finished_=0,read_rejected_=0,read_starts_=0;
    void run_region_reads(Ref<NativeBlockRegionStore> store);
    int64_t request_read(const String &asset,Vector3i region,const PackedByteArray &expected,const PackedByteArray &checkpoint,int64_t epoch,bool metadata=false,bool strict_checkpoint=false);
    Array poll_reads(int max_results,bool models);
    bool reference_in_file(const String &path,std::set<String> &keep) const;
    bool retire_unreferenced();
protected:
    static void _bind_methods();
public:
    ~NativeRegionWorldArchive();
    bool configure(const Ref<RefCounted> &archive,const Ref<NativeStructuresSnapshot> &codec,bool metadata_first=false);
    bool acquire(const String &absolute_path);
    void release();
    PackedByteArray encode(const Dictionary &sections) const;
    Dictionary decode(const PackedByteArray &bytes) const;
    PackedByteArray read(const String &absolute_path) const;
    int64_t publish(const String &absolute_path,const PackedByteArray &bytes);
    Dictionary storage_stats() const;
    Dictionary read_storage_region(Vector3i region,const PackedByteArray &expected,const PackedByteArray &checkpoint=PackedByteArray()) const;
    // Queue request/poll/stats calls never wait for the store's I/O mutex.
    // Lifecycle calls have one owner; release drains and joins before closing.
    bool start_region_reads(int request_limit=8,int64_t byte_limit=8*(2*1024*1024+96));
    int64_t request_region_read(Vector3i region,const PackedByteArray &expected,const PackedByteArray &checkpoint,int64_t epoch);
    int64_t request_model_region_read(const String &asset,Vector3i region,const PackedByteArray &expected,const PackedByteArray &checkpoint,int64_t epoch);
    // Strict reads certify membership in this checkpoint, never the active catalog.
    int64_t request_checkpoint_region_read(Vector3i region,const PackedByteArray &expected,const PackedByteArray &checkpoint,int64_t epoch);
    int64_t request_model_checkpoint_region_read(const String &asset,Vector3i region,const PackedByteArray &expected,const PackedByteArray &checkpoint,int64_t epoch);
    int64_t request_model_metadata(const String &asset,const PackedByteArray &checkpoint,int64_t epoch);
    bool configure_checkpoint_retention(int lease_limit);
    int64_t retain_read_checkpoint(const String &asset,const PackedByteArray &checkpoint);
    bool release_read_checkpoint(int64_t lease);
    Array poll_model_region_reads(int max_results=4);
    Array poll_region_reads(int max_results=4);
    void stop_region_reads();
    void join_region_reads();
    Dictionary region_read_stats() const;
    Dictionary published_region_index(int64_t after_revision=0) const;
    bool validate_snapshot(const PackedByteArray &bytes) const {return codec_.is_valid()&&codec_->validate_storage_snapshot(bytes);}
};
}
