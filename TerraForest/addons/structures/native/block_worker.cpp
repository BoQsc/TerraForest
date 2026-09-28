// SPDX-License-Identifier: 0BSD
#include "block_world.hpp"

namespace terraforest {
NativeBlockWorld::~NativeBlockWorld() {
    {
        std::lock_guard<std::mutex> lock(worker_mutex);
        worker_stopping=true;
    }
    worker_wake.notify_all();
    if(worker_thread.joinable())worker_thread.join();
}

void NativeBlockWorld::submit_bake(BlockKey key,uint64_t ticket,const std::array<uint16_t,5832> &halo) {
    // Scene-thread only. launch() never submits while an earlier result is owned.
    if(!worker_thread.joinable()) {
        worker_thread=std::thread(&NativeBlockWorld::worker_loop,this);
        ++worker_starts;
    }
    {
        std::lock_guard<std::mutex> lock(worker_mutex);
        submitted_key=key;submitted_ticket=ticket;submitted_halo=halo;
        worker_pending=true;
    }
    worker_active=true;worker_key=key;++worker_submissions;
    worker_wake.notify_one();
}

void NativeBlockWorld::worker_loop() {
    for(;;) {
        BlockKey key;uint64_t ticket;
        std::array<uint16_t,5832> halo;
        {
            std::unique_lock<std::mutex> lock(worker_mutex);
            worker_wake.wait(lock,[this]{return worker_stopping||worker_pending;});
            if(worker_stopping)return;
            key=submitted_key;ticket=submitted_ticket;halo=submitted_halo;
            worker_pending=false;
        }
        // No lock is held during expensive work. Destruction joins an active bake;
        // queued work and completed results are discarded when stopping.
        BlockBake result=bake(key,ticket,std::move(halo));
        {
            std::lock_guard<std::mutex> lock(worker_mutex);
            if(worker_stopping)return;
            worker_result=std::move(result);worker_ready=true;
        }
        worker_wake.notify_all();
    }
}

bool NativeBlockWorld::take_bake(BlockBake &result,bool wait) {
    if(!worker_active)return false;
    std::unique_lock<std::mutex> lock(worker_mutex);
    if(wait)worker_wake.wait(lock,[this]{return worker_ready||worker_stopping;});
    if(!worker_ready)return false;
    result=std::move(worker_result);worker_ready=false;
    worker_active=false;++worker_consumed;
    return true;
}
}
