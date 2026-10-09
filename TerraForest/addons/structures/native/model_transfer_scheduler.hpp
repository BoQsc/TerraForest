// SPDX-License-Identifier: 0BSD
#pragma once
#include "region_world_archive.hpp"
#include "static_history.hpp"

namespace terraforest {
// Shared with the weakly registered collection. Destroying a scheduler must not
// release the only backing checkpoint for a still-live unavailable collection.
struct ModelCheckpointLease {
    Ref<NativeRegionWorldArchive> archive;
    PackedByteArray checkpoint;
    int64_t handle=0;
    ~ModelCheckpointLease(){if(archive.is_valid()&&handle)archive->release_read_checkpoint(handle);}
};
class NativeModelTransferScheduler : public RefCounted {
    GDCLASS(NativeModelTransferScheduler,RefCounted)
    struct Collection {uint64_t id=0;std::shared_ptr<ModelCheckpointLease> lease;};
    enum Stage {QUEUED,READING,READY,TRANSFERRING,DONE};
    struct Job {
        int64_t ticket=0,epoch=0,read_ticket=0,transfer_ticket=0;
        String asset,result,error;
        Vector3i region;
        PackedByteArray expected,packet;
        int priority=0;
        Stage stage=QUEUED;
        bool retiring=false,cancelled=false;
        uint64_t last_served=0;
    };
    Ref<NativeRegionWorldArchive> archive;
    Ref<NativeStaticHistory> history;
    std::map<String,Collection> collections;
    std::map<int64_t,Job> jobs;
    int job_limit=8;
    int64_t byte_limit=64*1024*1024,epoch=0,next_ticket=1;
    uint64_t serial=0;
    bool busy=false,stopping=false;
    int64_t ticks=0,last_records=0,last_bytes=0,last_operations=0,last_usec=0,peak_usec=0;
    static constexpr int64_t PACKET_RESERVATION=5600232;
    static NativeStaticBatch *resolve(uint64_t id);
    void finish(Job &job,const String &result,const String &error=String());
    void cancel_job(Job &job);
    bool collection_busy(const Job &job) const;
protected:
    static void _bind_methods();
public:
    ~NativeModelTransferScheduler();
    bool configure(const Ref<NativeRegionWorldArchive> &source,const Ref<NativeStaticHistory> &journal,int max_jobs,int64_t max_bytes);
    bool register_collection(const String &asset,NativeStaticBatch *collection,const PackedByteArray &checkpoint);
    bool unregister_collection(const String &asset);
    int64_t request(const String &asset,Vector3i region,const PackedByteArray &expected,bool retire,int priority,int64_t request_epoch);
    bool cancel(int64_t ticket);
    bool set_epoch(int64_t value);
    bool stop();
    Dictionary tick(int max_records=256,int max_hash_bytes=65536,int max_usec=500,int max_operations=8);
    Array poll(int max_results=8);
    Dictionary stats() const;
};
}
