// SPDX-License-Identifier: 0BSD
#pragma once
#include "regional_water.hpp"
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <mutex>
#include <atomic>
#include <cstring>
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
namespace terraforest {
// One serialized I/O owner. Immutable blobs/checkpoints; no mutable current-world
// pointer. The compound world archive must own the selected checkpoint identity.
class NativeWaterRegionStore : public godot::RefCounted {
 GDCLASS(NativeWaterRegionStore,godot::RefCounted)
 using Bytes=godot::PackedByteArray;
 std::mutex mutex;
 godot::String directory;
 HANDLE lease=INVALID_HANDLE_VALUE;
 Bytes indexed_id,indexed_catalog;
 int64_t index_loads=0,index_hits=0;
 bool index(const Bytes &id){
  if(id.size()!=32)return false;
  if(id==indexed_id){++index_hits;return true;}
  Bytes bytes;std::map<uint64_t,Bytes> checked;
  if(!read(id,".checkpoint",CATALOG_LIMIT,bytes)||!parse(bytes,checked))return false;
  indexed_catalog=bytes;indexed_id=id;++index_loads;return true;
 }
 int64_t lower_bound(uint64_t wanted) const {
  int64_t lo=0,hi=indexed_catalog.decode_u32(8);
  while(lo<hi){int64_t mid=lo+(hi-lo)/2;if(indexed_catalog.decode_u64(12+mid*40)<wanted)lo=mid+1;else hi=mid;}
  return lo;
 }
 static constexpr int64_t REGION_LIMIT=8*1024*1024,CATALOG_LIMIT=4*1024*1024;
 static Bytes hash(const Bytes &b){godot::Ref<godot::HashingContext> h;h.instantiate();h->start(godot::HashingContext::HASH_SHA256);h->update(b);return h->finish();}
 static godot::Dictionary result(bool ok){godot::Dictionary d;d["ok"]=ok;return d;}
 static uint64_t key(const godot::Vector3i &p){return (uint64_t(p.x)<<24)|(uint64_t(p.y)<<12)|uint64_t(p.z);}
 static bool valid(const godot::Vector3i &p){return p.x>=0&&p.x<500&&p.y>=0&&p.y<64&&p.z>=0&&p.z<500;}
 static godot::Vector3i coordinate(uint64_t k){return godot::Vector3i((k>>24)&4095,(k>>12)&4095,k&4095);}
 godot::String path(const Bytes &id,const char *suffix) const{return directory.path_join(id.hex_encode()+suffix);}
 static bool read_file(const godot::String &path,int64_t limit,Bytes &data){
  auto name=path.utf16();HANDLE f=CreateFileW((LPCWSTR)name.get_data(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
  if(f==INVALID_HANDLE_VALUE)return false;LARGE_INTEGER size{};bool ok=GetFileSizeEx(f,&size)&&size.QuadPart>0&&size.QuadPart<=limit;
  if(ok)ok=data.resize(size.QuadPart)==godot::OK;
  DWORD got=0;if(ok)ok=ReadFile(f,data.ptrw(),DWORD(size.QuadPart),&got,nullptr)&&got==size.QuadPart;CloseHandle(f);return ok;
 }
 bool read(const Bytes &id,const char *suffix,int64_t limit,Bytes &data) const{return id.size()==32&&read_file(path(id,suffix),limit,data)&&hash(data)==id;}
 bool publish(const Bytes &data,const char *suffix,Bytes &id){
  id=hash(data);auto target=path(id,suffix);auto target_name=target.utf16();
  if(GetFileAttributesW((LPCWSTR)target_name.get_data())!=INVALID_FILE_ATTRIBUTES){Bytes old;return read(id,suffix,data.size(),old)&&old==data;}
  static std::atomic<uint64_t> sequence{0};
  auto temporary=target+".pending."+godot::String::num_uint64(GetCurrentProcessId())+"."+godot::String::num_uint64(++sequence);auto name=temporary.utf16();
  HANDLE f=CreateFileW((LPCWSTR)name.get_data(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL|FILE_FLAG_WRITE_THROUGH,nullptr);
  if(f==INVALID_HANDLE_VALUE)return false;DWORD written=0;
  bool ok=WriteFile(f,data.ptr(),DWORD(data.size()),&written,nullptr)&&written==data.size()&&FlushFileBuffers(f);CloseHandle(f);
  Bytes verified;ok=ok&&read_file(temporary,data.size(),verified)&&verified==data;
  if(ok)ok=MoveFileExW((LPCWSTR)name.get_data(),(LPCWSTR)target_name.get_data(),MOVEFILE_WRITE_THROUGH);
  if(!ok)DeleteFileW((LPCWSTR)name.get_data());return ok;
 }
 static bool packet_valid(const godot::Vector3i &p,const Bytes &packet){
  godot::Ref<NativeRegionalWater> validator;validator.instantiate();return validator->restore_region_snapshot(p,packet,0,true);
 }
 static bool parse(const Bytes &bytes,std::map<uint64_t,Bytes> &entries){
  if(bytes.size()<12||bytes.size()>CATALOG_LIMIT||std::memcmp(bytes.ptr(),"TFWC\1\0\0\0",8))return false;
  uint32_t count=bytes.decode_u32(8);if(count>65536||bytes.size()!=12+int64_t(count)*40)return false;
  uint64_t previous=0;for(uint32_t i=0;i<count;++i){int64_t at=12+int64_t(i)*40;uint64_t k=bytes.decode_u64(at);auto p=coordinate(k);
   if(!valid(p)||key(p)!=k||(i&&k<=previous))return false;previous=k;entries.emplace(k,bytes.slice(at+8,at+40));}
  return true;
 }
 void close_unlocked(){if(lease!=INVALID_HANDLE_VALUE)CloseHandle(lease);lease=INVALID_HANDLE_VALUE;directory=godot::String();indexed_id=Bytes();indexed_catalog=Bytes();index_loads=index_hits=0;}
protected:
 static void _bind_methods(){
  godot::ClassDB::bind_method(godot::D_METHOD("publish_water_snapshot","snapshot"),&NativeWaterRegionStore::publish_water_snapshot);
  godot::ClassDB::bind_method(godot::D_METHOD("expand_water_snapshot","snapshot"),&NativeWaterRegionStore::expand_water_snapshot);
  godot::ClassDB::bind_method(godot::D_METHOD("checkpoint_page","checkpoint","cursor","limit"),&NativeWaterRegionStore::checkpoint_page);
  godot::ClassDB::bind_method(godot::D_METHOD("index_stats"),&NativeWaterRegionStore::index_stats);
  godot::ClassDB::bind_method(godot::D_METHOD("open_store","absolute_directory"),&NativeWaterRegionStore::open_store);
  godot::ClassDB::bind_method(godot::D_METHOD("close"),&NativeWaterRegionStore::close);
  godot::ClassDB::bind_method(godot::D_METHOD("publish_region","coordinate","packet"),&NativeWaterRegionStore::publish_region);
  godot::ClassDB::bind_method(godot::D_METHOD("publish_checkpoint","coordinates","digests"),&NativeWaterRegionStore::publish_checkpoint);
  godot::ClassDB::bind_method(godot::D_METHOD("read_region","checkpoint","coordinate"),&NativeWaterRegionStore::read_region);
 }
public:
 ~NativeWaterRegionStore(){close();}
 bool open_store(const godot::String &absolute_directory){std::lock_guard<std::mutex> lock(mutex);if(lease!=INVALID_HANDLE_VALUE||!absolute_directory.is_absolute_path())return false;
  if(godot::DirAccess::make_dir_recursive_absolute(absolute_directory)!=godot::OK)return false;
  auto name=absolute_directory.path_join("writer.lock").utf16();lease=CreateFileW((LPCWSTR)name.get_data(),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
  if(lease==INVALID_HANDLE_VALUE)return false;directory=absolute_directory;return true;
 }
 void close(){std::lock_guard<std::mutex> lock(mutex);close_unlocked();}
 godot::Dictionary publish_region(const godot::Vector3i &p,const Bytes &packet){std::lock_guard<std::mutex> lock(mutex);
  if(lease==INVALID_HANDLE_VALUE||!valid(p)||packet.size()>REGION_LIMIT||!packet_valid(p,packet))return result(false);
  Bytes id;if(!publish(packet,".water",id))return result(false);auto out=result(true);out["digest"]=id;return out;
 }
 godot::Dictionary publish_checkpoint(const godot::PackedInt32Array &coordinates,const godot::Array &digests){std::lock_guard<std::mutex> lock(mutex);
  if(lease==INVALID_HANDLE_VALUE||coordinates.size()%3||digests.size()!=coordinates.size()/3||digests.size()>65536)return result(false);
  std::map<uint64_t,Bytes> entries;
  for(int64_t i=0;i<digests.size();++i){godot::Vector3i p(coordinates[i*3],coordinates[i*3+1],coordinates[i*3+2]);if(!valid(p)||digests[i].get_type()!=godot::Variant::PACKED_BYTE_ARRAY)return result(false);
   Bytes id=digests[i],packet;if(!entries.emplace(key(p),id).second||!read(id,".water",REGION_LIMIT,packet)||!packet_valid(p,packet))return result(false);
  }
  Bytes bytes;bytes.resize(12+entries.size()*40);std::memcpy(bytes.ptrw(),"TFWC\1\0\0\0",8);bytes.encode_u32(8,entries.size());int64_t at=12;
  for(const auto &[k,id]:entries){bytes.encode_u64(at,k);std::memcpy(bytes.ptrw()+at+8,id.ptr(),32);at+=40;}
  Bytes id;if(!publish(bytes,".checkpoint",id))return result(false);auto out=result(true);out["checkpoint"]=id;out["regions"]=int64_t(entries.size());return out;
 }
 godot::Dictionary read_region(const Bytes &checkpoint,const godot::Vector3i &p){std::lock_guard<std::mutex> lock(mutex);
  if(lease==INVALID_HANDLE_VALUE||!valid(p))return result(false);
  if(!index(checkpoint))return result(false);
  int64_t n=lower_bound(key(p));if(n>=indexed_catalog.decode_u32(8)||indexed_catalog.decode_u64(12+n*40)!=key(p))return result(false);
  Bytes id=indexed_catalog.slice(20+n*40,52+n*40),packet;
  if(!read(id,".water",REGION_LIMIT,packet)||!packet_valid(p,packet))return result(false);
  auto out=result(true);out["packet"]=packet;out["digest"]=id;return out;
 }
 godot::Dictionary checkpoint_page(const Bytes &checkpoint,int64_t cursor,int64_t limit){
  std::lock_guard<std::mutex> lock(mutex);
  if(lease==INVALID_HANDLE_VALUE||cursor<0||limit<1||limit>256||!index(checkpoint))return result(false);
  int64_t count=indexed_catalog.decode_u32(8);if(cursor>count)return result(false);
  int64_t end=std::min(count,cursor+limit);godot::PackedInt32Array coordinates;Bytes digests;
  coordinates.resize((end-cursor)*3);digests.resize((end-cursor)*32);
  for(int64_t n=cursor;n<end;++n){auto p=coordinate(indexed_catalog.decode_u64(12+n*40));int64_t i=n-cursor;
   coordinates.set(i*3,p.x);coordinates.set(i*3+1,p.y);coordinates.set(i*3+2,p.z);
   std::memcpy(digests.ptrw()+i*32,indexed_catalog.ptr()+20+n*40,32);
  }
  auto out=result(true);out["coordinates"]=coordinates;out["digests"]=digests;out["cursor"]=end;out["complete"]=end==count;return out;
 }
 // Save-worker adapter. No live water references; no selected checkpoint mutation.
 Bytes publish_water_snapshot(const Bytes &snapshot){
  godot::Ref<NativeRegionalWater> water;water.instantiate();if(!water->restore_snapshot(snapshot))return water->validate_snapshot(snapshot)?snapshot:Bytes();
  auto keys=water->edited_region_coordinates();if(keys.is_empty())return snapshot;
  auto catalog=water->snapshot_catalog(snapshot);auto base=water->capture_unarchived_snapshot(catalog);if(base.is_empty())return {};
  godot::Array ids;
  for(int64_t i=0;i<keys.size();i+=3){godot::Vector3i p(keys[i],keys[i+1],keys[i+2]);auto reply=publish_region(p,water->capture_region_snapshot(p));
   if(!bool(reply["ok"]))return {};ids.append(reply["digest"]);
  }
  auto checkpoint=publish_checkpoint(keys,ids);if(!bool(checkpoint["ok"]))return {};
  Bytes id=checkpoint["checkpoint"],out;if(base.size()>64*1024*1024-48)return {};
  out.resize(48+base.size());std::memcpy(out.ptrw(),"TFWS\1\0\0\0",8);out.encode_u64(8,base.size());
  std::memcpy(out.ptrw()+16,id.ptr(),32);std::memcpy(out.ptrw()+48,base.ptr(),base.size());return out;
 }
 Bytes expand_water_snapshot(const Bytes &snapshot){
  godot::Ref<NativeRegionalWater> water;water.instantiate();
  if(snapshot.size()<8||std::memcmp(snapshot.ptr(),"TFWS\1\0\0\0",8))return water->validate_snapshot(snapshot)?snapshot:Bytes();
  if(snapshot.size()<48||snapshot.size()>64*1024*1024||snapshot.decode_u64(8)!=uint64_t(snapshot.size()-48))return {};
  Bytes id=snapshot.slice(16,48),base=snapshot.slice(48);if(!water->restore_snapshot(base)||!water->edited_region_coordinates().is_empty())return {};
  int64_t cursor=0;
  for(;;){auto page=checkpoint_page(id,cursor,256);if(!bool(page["ok"]))return {};
   godot::PackedInt32Array keys=page["coordinates"];
   for(int64_t i=0;i<keys.size();i+=3){godot::Vector3i p(keys[i],keys[i+1],keys[i+2]);auto region=read_region(id,p);
    if(!bool(region["ok"])||!water->restore_region_snapshot(p,region["packet"],water->survey_revision_id(),true))return {};
   }
   if(bool(page["complete"]))break;cursor=page["cursor"];
  }
  return water->capture_snapshot(water->snapshot_catalog(base));
 }
 godot::Dictionary index_stats(){std::lock_guard<std::mutex> lock(mutex);godot::Dictionary out;out["loads"]=index_loads;out["hits"]=index_hits;out["bytes"]=indexed_catalog.size()+indexed_id.size();return out;}
};
}
