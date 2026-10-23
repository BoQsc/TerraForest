// SPDX-License-Identifier: 0BSD
#pragma once
#include <atomic>
#include <algorithm>
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

namespace terraforest {
// Immutable generation/storage jobs only. One parallel batch per extension prevents
// simultaneous preview/creation requests multiplying worker counts. The caller
// keeps its World locked for the complete batch; workers touch disjoint outputs.
inline std::atomic_flag generation_batch_busy=ATOMIC_FLAG_INIT;
template<class F> int generation_parallel_for(int count,const F &function,int minimum_count=16384,int max_workers=4){
 const unsigned logical=GetActiveProcessorCount(ALL_PROCESSOR_GROUPS);
 const int workers=std::min(max_workers,std::min(4,int(std::max(1u,logical/2))));
 if(count<minimum_count||workers<=1){for(int i=0;i<count;i++)function(i);return 1;}
 if(generation_batch_busy.test_and_set(std::memory_order_acquire)){
  for(int i=0;i<count;i++)function(i);return 1;
 }
 struct Range{const F *function;int first,last;};
 Range ranges[4];HANDLE handles[3]={};int used=1;
 auto entry=[](LPVOID pointer)->DWORD{
  const auto &range=*static_cast<Range*>(pointer);
  for(int i=range.first;i<range.last;i++)(*range.function)(i);return 0;
 };
 for(int worker=0;worker<workers;worker++)ranges[worker]={&function,count*worker/workers,count*(worker+1)/workers};
 for(int worker=1;worker<workers;worker++){
  handles[worker-1]=CreateThread(nullptr,0,entry,&ranges[worker],0,nullptr);
  if(handles[worker-1])used++;
  else entry(&ranges[worker]); // Thread exhaustion retains correct serial work.
 }
 entry(&ranges[0]);
 for(int worker=1;worker<workers;worker++)if(handles[worker-1]){
  WaitForSingleObject(handles[worker-1],INFINITE);CloseHandle(handles[worker-1]);
 }
 generation_batch_busy.clear(std::memory_order_release);return used;
}
}
