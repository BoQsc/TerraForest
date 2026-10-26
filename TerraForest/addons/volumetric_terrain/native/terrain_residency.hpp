// SPDX-License-Identifier: 0BSD
#pragma once
#include "terrain_region_store.hpp"
#include <godot_cpp/classes/ref.hpp>
#include <algorithm>
#include <chrono>
#include <godot_cpp/variant/dictionary.hpp>
namespace terraforest {
// Single terrain-worker owner. Clean page faults read verified immutable regional
// products. Dirty samples stay pinned until a successful compound-root commit.
class TerrainResidency final : public PageAccess {
 godot::Ref<NativeTerrainRegionStore> store_;
 godot::PackedByteArray reference_;
 int limit_,count_=0,high_=0,head_=-1,tail_=-1;
 int64_t faults_=0,evictions_=0,failed_=0,storage_failed_=0,scan_high_=0;
 double fault_us_=0,fault_max_us_=0;
 void detach(World&w,int i){
  Page&p=w.pages[i];if(p.resident_previous>=0)w.pages[p.resident_previous].resident_next=p.resident_next;else head_=p.resident_next;
  if(p.resident_next>=0)w.pages[p.resident_next].resident_previous=p.resident_previous;else tail_=p.resident_previous;
  p.resident_previous=p.resident_next=-1;
 }
 bool pinned(const World&w,const Page&p)const{
  if(p.storage_version!=p.clean_version)return true;
  if(!w.pages_pinned)return false;
  int v=int(p.key-1),x=v%WORLD_PAGE_COLUMNS;v/=WORLD_PAGE_COLUMNS;int z=v%WORLD_PAGE_COLUMNS,y=v/WORLD_PAGE_COLUMNS;
  return x>=fl(w.pin_lo.x)/16&&x<=fl(w.pin_hi.x)/16&&z>=fl(w.pin_lo.z)/16&&z<=fl(w.pin_hi.z)/16&&y>=fl(w.pin_lo.y)/16&&y<=fl(w.pin_hi.y)/16;
 }
public:
 TerrainResidency(godot::Ref<NativeTerrainRegionStore> store,const godot::PackedByteArray &reference,int limit):store_(store),reference_(reference),limit_(limit){}
 int resident_high()const{return high_;}
 void checkpoint(const godot::PackedByteArray&reference){reference_=reference;}
 void touch(World&w,int i)override{
  if(tail_==i)return;detach(w,i);--count_;inserted(w,i);
 }
 void inserted(World&w,int i)override{
  auto&p=w.pages[i];p.resident_previous=tail_;p.resident_next=-1;
  if(tail_>=0)w.pages[tail_].resident_next=i;else head_=i;tail_=i;++count_;high_=std::max(high_,count_);
 }
 bool admit(World&w)override{
  // At most the fixed resident budget is traversed. No scan over historical pages.
  int scanned=0;
  while(count_>=limit_){int victim=head_;
   while(victim>=0&&pinned(w,w.pages[victim])){victim=w.pages[victim].resident_next;++scanned;}
   scan_high_=std::max(scan_high_,int64_t(scanned));if(victim<0){++failed_;return false;}
   auto&p=w.pages[victim];detach(w,victim);--count_;tr_free(p.d);tr_free(p.mat);p.d=nullptr;p.mat=nullptr;++evictions_;
  }
  return true;
 }
 bool load(World&w,int i)override{
  const auto started=w.profile_mesh?std::chrono::steady_clock::now():std::chrono::steady_clock::time_point{};
  if(!admit(w)){tr_oom=true;return false;}
  godot::PackedByteArray bytes=store_->read_page(reference_,w.pages[i].key);
  if(bytes.size()!=PAGE_SAMPLES*3){++failed_;++storage_failed_;tr_oom=true;return false;}
  i16*d=static_cast<i16*>(tr_alloc(PAGE_SAMPLES*2));u8*m=static_cast<u8*>(tr_alloc(PAGE_SAMPLES));
  if(!d||!m){if(d)tr_free(d);if(m)tr_free(m);++failed_;tr_oom=true;return false;}
  copy_bytes(d,bytes.ptr(),PAGE_SAMPLES*2);copy_bytes(m,bytes.ptr()+PAGE_SAMPLES*2,PAGE_SAMPLES);
  auto&p=w.pages[i];p.d=d;p.mat=m;inserted(w,i);++faults_;
  if(w.profile_mesh){double us=std::chrono::duration<double,std::micro>(std::chrono::steady_clock::now()-started).count();fault_us_+=us;fault_max_us_=std::max(fault_max_us_,us);}
  return true;
 }
 godot::Dictionary stats(const World&w)const{
  godot::Dictionary d;d["active"]=true;d["catalog_pages"]=w.pages.n;d["resident_pages"]=count_;d["resident_high"]=high_;d["resident_limit"]=limit_;d["sample_bytes"]=int64_t(count_)*PAGE_SAMPLES*3;d["faults"]=faults_;d["evictions"]=evictions_;d["failures"]=failed_;d["storage_failures"]=storage_failed_;d["eviction_scan_high"]=scan_high_;d["profiled_fault_us"]=fault_us_;d["profiled_fault_max_us"]=fault_max_us_;return d;
 }
 // An atomic edit may allocate new pages and then roll back on admission/OOM.
 void removed(World&w,int i)override{detach(w,i);--count_;}
};
}
