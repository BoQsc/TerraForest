// SPDX-License-Identifier: 0BSD
#pragma once
#include "block_region_store.hpp"
#include <condition_variable>
#include <deque>
#include <thread>

namespace terraforest {
// Scene-owner API; the worker owns the store and never accesses scene objects.
class NativeBlockRegionIO : public RefCounted {
    GDCLASS(NativeBlockRegionIO,RefCounted)
    enum Operation { OPEN, READ, PUBLISH, REMOVE, COLLECT, INDEX };
    struct Request {
        Operation operation=OPEN;
        int64_t ticket=0,reserved=0;
        Vector3i region;
        Array packets,expected;
        PackedByteArray checksum;
        int budget=0;
    };
    struct Completion {Dictionary value;int64_t reserved=0;};
    mutable std::mutex mutex_;
    std::condition_variable wake_;
    std::thread worker_;
    std::deque<Request> pending_;
    std::deque<Completion> completed_;
    bool running_=false,ready_=false,stopping_=false,active_=false;
    int request_limit_=0,outstanding_=0,high_requests_=0;
    int64_t byte_limit_=0,reserved_=0,high_bytes_=0,next_ticket_=1;
    int64_t accepted_=0,finished_=0,rejected_=0,starts_=0;
    int64_t enqueue(Request request);
    void run(String path,bool recover,Request opening);
    static const char *operation_name(Operation operation);
protected:
    static void _bind_methods();
public:
    ~NativeBlockRegionIO();
    int64_t start(const String &absolute_directory,int request_limit,int64_t byte_limit,bool recover_backup=false);
    int64_t read_region(Vector3i region);
    int64_t publish_regions(const Array &packets,const Array &expected_checksums);
    int64_t remove_region(Vector3i region,const PackedByteArray &expected_checksum);
    int64_t collect_garbage(int max_inspected);
    int64_t list_regions();
    Array poll(int max_results=16);
    void request_stop();
    void join();
    Dictionary stats() const;
};
}
