// SPDX-License-Identifier: 0BSD
#pragma once
#include <atomic>
#include <cstdint>
#include <godot_cpp/variant/dictionary.hpp>

namespace terraforest {
// One coherent observation, independent of the terrain owner's long-held lock.
// Update at command/checkpoint boundaries, never per density sample.
class GenerationBakeProgress {
 std::atomic<uint64_t> value_{0};
public:
 enum State{IDLE=0,RUNNING=1,COMPLETE=2,FAILED=3,CANCELLED=4};
 enum Phase{NONE=0,APPLYING=1,CHECKPOINT=2};
 void reset(){value_.store(0,std::memory_order_release);}
 void publish(State state,Phase phase,int completed,int total,int checkpoints){
  uint64_t value=uint64_t(completed)|(uint64_t(total)<<16)|(uint64_t(checkpoints)<<32)|(uint64_t(state)<<48)|(uint64_t(phase)<<56);
  value_.store(value,std::memory_order_release);
 }
 godot::Dictionary read()const{
  const uint64_t value=value_.load(std::memory_order_acquire);
  godot::Dictionary result;
  result["completed"]=int(value&65535);result["total"]=int((value>>16)&65535);
  result["checkpoints"]=int((value>>32)&65535);result["state"]=int((value>>48)&255);result["phase"]=int(value>>56);
  return result;
 }
};
}
