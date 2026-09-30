// SPDX-License-Identifier: 0BSD
#pragma once
#include "fallible_buffer.hpp"
#include <atomic>
#include <cstddef>

namespace terraforest::experimental {
// Shared allocator admission, not a world lock. This owner and its upstream
// allocator context MUST outlive every buffer allocated through allocator().
// Charges requested heap bytes plus our header, not opaque malloc overhead.
class SnapshotMemoryBudget {
 struct alignas(std::max_align_t) Header{size_t charged;};
 const size_t limit_;
 BufferAllocator upstream_;
 std::atomic<size_t> used_{0},peak_{0},denied_{0};
 void*allocate(size_t bytes){
  if(bytes>std::numeric_limits<size_t>::max()-sizeof(Header)||!upstream_.allocate||!upstream_.release){denied_++;return nullptr;}
  const size_t charged=bytes+sizeof(Header);
  size_t current=used_.load(std::memory_order_relaxed);
  do{
   if(current>limit_||charged>limit_-current){denied_++;return nullptr;}
  }while(!used_.compare_exchange_weak(current,current+charged,std::memory_order_relaxed));
  size_t peak=peak_.load(std::memory_order_relaxed);
  while(peak<current+charged&&!peak_.compare_exchange_weak(peak,current+charged,std::memory_order_relaxed)){}
  void*raw=upstream_.allocate(upstream_.context,charged);
  if(!raw){used_.fetch_sub(charged,std::memory_order_relaxed);return nullptr;}
  Header*h=::new(raw)Header{charged};return h+1;
 }
 void release(void*pointer){
  if(!pointer)return;
  Header*h=static_cast<Header*>(pointer)-1;size_t charged=h->charged;
  upstream_.release(upstream_.context,h);
  used_.fetch_sub(charged,std::memory_order_relaxed);
 }
public:
 explicit SnapshotMemoryBudget(size_t limit,const BufferAllocator&upstream=BufferAllocator{}):limit_(limit),upstream_(upstream){}
 SnapshotMemoryBudget(const SnapshotMemoryBudget&)=delete;
 SnapshotMemoryBudget&operator=(const SnapshotMemoryBudget&)=delete;
 size_t used()const{return used_.load(std::memory_order_relaxed);}
 size_t peak()const{return peak_.load(std::memory_order_relaxed);}
 size_t denied()const{return denied_.load(std::memory_order_relaxed);}
 size_t limit()const{return limit_;}
 BufferAllocator allocator(){return {this,[](void*p,size_t n){return static_cast<SnapshotMemoryBudget*>(p)->allocate(n);},[](void*p,void*v){static_cast<SnapshotMemoryBudget*>(p)->release(v);}};}
};
}
