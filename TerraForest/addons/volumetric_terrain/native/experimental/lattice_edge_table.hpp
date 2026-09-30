// SPDX-License-Identifier: 0BSD
#pragma once
#include "fallible_buffer.hpp"
#include "core.h"
#include <algorithm>

namespace terraforest::experimental {
// The fixed six-tetrahedron split uses only seven monotone lattice directions.
// Each edge is keyed by its lower endpoint and direction; no hash nodes are needed.
class LatticeEdgeTable {
 FallibleBuffer<u32> entries_;
 int x0_=0,z0_=0,n_=0;bool rolling_=true;size_t live_=0;
public:
 static constexpr u32 absent=std::numeric_limits<u32>::max();
 static constexpr size_t invalid_slot=std::numeric_limits<size_t>::max();
 bool initialize(int x,int z,int size,bool rolling,BufferAllocator allocator){
  x0_=x;z0_=z;n_=size+1;rolling_=rolling;live_=0;
  entries_.set_allocator(allocator);
  if(!entries_.resize(size_t(n_)*n_*7*(rolling?2:257)))return false;
  std::fill(entries_.begin(),entries_.end(),absent);return true;
 }
 size_t slot(u32 a,u32 b)const{
  constexpr u32 stride=2049,plane=stride*stride;
  int ax=int(a%stride),az=int((a/stride)%stride),ay=int(a/plane);
  int bx=int(b%stride),bz=int((b/stride)%stride),by=int(b/plane);
  int dx=bx-ax,dy=by-ay,dz=bz-az;
  if(dx<0||dx>1||dy<0||dy>1||dz<0||dz>1||!(dx||dy||dz)||ay>256||by>256)return invalid_slot;
  ax-=x0_;az-=z0_;
  if(ax<0||ax>=n_||az<0||az>=n_||ax+dx>=n_||az+dz>=n_)return invalid_slot;
  unsigned direction=unsigned(dx|(dy<<1)|(dz<<2))-1;
  return (size_t(rolling_?(ay&1):ay)*n_*n_+az*n_+ax)*7+direction;
 }
 u32 get(size_t slot)const{return entries_[slot];}
 void put(size_t slot,u32 value){if(entries_[slot]==absent)live_++;entries_[slot]=value;}
 void retire(int y){
  if(!rolling_)return;
  size_t begin=size_t(y&1)*n_*n_*7,end=begin+size_t(n_)*n_*7;
  for(size_t i=begin;i<end;i++){if(entries_[i]!=absent)live_--;entries_[i]=absent;}
 }
 void clear(){entries_.clear();live_=0;}
 bool empty()const{return live_==0;}
 size_t size()const{return live_;}
 size_t slots()const{return entries_.size();}
};
} // namespace terraforest::experimental
